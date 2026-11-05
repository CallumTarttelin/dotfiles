pub mod archive;
pub mod gateway;
pub mod journal;
pub mod keys;
pub mod provision;
mod sse;

pub fn private_umask() {
    nix::sys::stat::umask(nix::sys::stat::Mode::from_bits_truncate(0o077));
}
