# NATS and Garage on Nixie

Nixie runs NATS with JetStream and single-node Garage for local applications.
All listeners bind to `127.0.0.1`; there are no Caddy routes or firewall openings.
Neither service's data is included in the current backup jobs.

## NATS

Connect to `nats://127.0.0.1:4222` from Nixie. Local clients do not need credentials.
The monitoring endpoint is `http://127.0.0.1:8222`.

JetStream stores data under `/var/lib/nats/jetstream`, with limits of 256 MiB
for memory streams and 10 GiB for file streams. The `nats` CLI is installed:

```sh
nats account info
nats stream add EVENTS --subjects 'events.>' --storage file --replicas 1 --defaults
nats request events.example 'hello' --raw
```

## Garage

Use S3 endpoint `http://127.0.0.1:3900`, region `garage`, and path-style bucket
addressing. Garage's RPC listener is `127.0.0.1:3901`. S3 website hosting and the
HTTP admin API are disabled.

The initial setup created bucket `default` and key `nixie-local`, with read,
write and owner access to that bucket. Its credentials are stored only on Nixie
in `/root/.config/garage/default.env` (mode `0600`). For an installed AWS CLI,
run as root on Nixie:

```sh
source /root/.config/garage/default.env
aws s3 ls s3://default/
```

Create separate buckets and keys for applications as needed:

```sh
sudo garage bucket create my-app
sudo garage key create my-app
sudo garage bucket allow --read --write my-app --key my-app
```

`garage key create` prints the credentials; store them in the application's
secret configuration. Garage stores metadata in `/var/lib/garage/meta` and
objects in `/var/lib/garage/data`. Its RPC secret is generated on first startup
and retained in `/var/lib/garage/rpc-secret`, outside the Nix store.

The initial layout assigns Nixie to zone `nixie` with capacity `100G` and
replication factor 1. This is a layout weight, not a disk quota; a single-node
Garage can use the available filesystem space. The layout, bucket and key are
persistent state initialized during deployment, rather than recreated by NixOS.
If the data directories are deleted, follow the [Garage manual setup](https://garagehq.deuxfleurs.fr/documentation/quick-start/#manual-configuration)
to initialize them again.

## Operations and validation

```sh
systemctl status nats garage
journalctl -u nats -u garage
sudo garage status
```

Validation included a full Nixie NixOS build, NATS configuration validation,
live loopback listener checks, a JetStream file-stream publish/read, and signed
S3 upload/download. Both the message and object survived service restarts;
the temporary stream and object were removed afterward.
