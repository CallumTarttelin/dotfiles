//! Observe protocol completion without changing or buffering the forwarded stream.
use serde_json::Value;

const MAX_EVENT: usize = 2 * 1024 * 1024;

pub(crate) struct Completion {
    endpoint: &'static str,
    line: Vec<u8>,
    data: Vec<u8>,
    event: Vec<u8>,
    size: usize,
    oversized: bool,
    cr: bool,
    line_nonempty: bool,
}

impl Completion {
    pub fn new(endpoint: &str) -> Option<Self> {
        let endpoint = match endpoint {
            "chat/completions" => "chat/completions",
            "responses" => "responses",
            "messages" => "messages",
            _ => return None,
        };
        Some(Self {
            endpoint,
            line: Vec::new(),
            data: Vec::new(),
            event: Vec::new(),
            size: 0,
            oversized: false,
            cr: false,
            line_nonempty: false,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> bool {
        let mut complete = false;
        for &byte in bytes {
            if byte == b'\n' && self.cr {
                self.cr = false;
                continue;
            }
            self.cr = byte == b'\r';
            if byte == b'\r' || byte == b'\n' {
                complete |= self.end_line();
            } else {
                self.line_nonempty = true;
                self.size = self.size.saturating_add(1);
                if self.size > MAX_EVENT {
                    self.oversized = true;
                    self.line.clear();
                    self.data.clear();
                    self.event.clear();
                } else {
                    self.line.push(byte);
                }
            }
        }
        complete
    }

    fn end_line(&mut self) -> bool {
        let line = std::mem::take(&mut self.line);
        if !std::mem::take(&mut self.line_nonempty) {
            let complete = !self.oversized && self.is_terminal();
            self.data.clear();
            self.event.clear();
            self.size = 0;
            self.oversized = false;
            return complete;
        }
        if self.oversized {
            return false;
        }
        if let Some(value) = line.strip_prefix(b"data:") {
            self.data
                .extend_from_slice(value.strip_prefix(b" ").unwrap_or(value));
            self.data.push(b'\n');
        } else if let Some(value) = line.strip_prefix(b"event:") {
            self.event = value.strip_prefix(b" ").unwrap_or(value).to_vec();
        }
        false
    }

    fn is_terminal(&self) -> bool {
        let data = self.data.strip_suffix(b"\n").unwrap_or(&self.data);
        if self.endpoint == "chat/completions" {
            return data == b"[DONE]";
        }
        let Ok(value) = serde_json::from_slice::<Value>(data) else {
            return false;
        };
        let Some(kind) = value["type"].as_str() else {
            return false;
        };
        if !self.event.is_empty() && self.event != kind.as_bytes() {
            return false;
        }
        match self.endpoint {
            "responses" => matches!(
                kind,
                "response.completed" | "response.failed" | "response.incomplete"
            ),
            "messages" => kind == "message_stop",
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_only_complete_terminal_events_across_every_chunk_boundary() {
        for (endpoint, input) in [
            ("chat/completions", "data: [DONE]\r\n\r\n"),
            (
                "responses",
                "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n",
            ),
            (
                "messages",
                "event: message_stop\rdata: {\"type\":\"message_stop\"}\r\r",
            ),
        ] {
            for split in 0..input.len() {
                let mut observer = Completion::new(endpoint).unwrap();
                let first = observer.feed(&input.as_bytes()[..split]);
                let second = observer.feed(&input.as_bytes()[split..]);
                assert!(first || second);
            }
        }
        for (endpoint, input) in [
            (
                "chat/completions",
                "data: {\"text\":\"data: [DONE]\\n\\n\"}\n\n",
            ),
            (
                "responses",
                "event: response.completed\ndata: {\"type\":\"response.output_text.delta\"}\n\n",
            ),
            ("responses", "event: response.completed\n\n"),
            ("messages", "data: {\"type\":\"content_block_stop\"}\n\n"),
        ] {
            assert!(!Completion::new(endpoint).unwrap().feed(input.as_bytes()));
        }
    }

    #[test]
    fn oversized_events_are_skipped_and_later_terminal_events_still_work() {
        let mut observer = Completion::new("chat/completions").unwrap();
        assert!(!observer.feed(b"data: "));
        assert!(!observer.feed(&vec![b'x'; MAX_EVENT + 1]));
        assert!(!observer.feed(b"[DONE]\n\n"));
        assert!(observer.feed(b"data: [DONE]\n\n"));
        assert!(
            !Completion::new("chat/completions")
                .unwrap()
                .feed(b"data: [DONE]\n")
        );
    }
}
