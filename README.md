# systemd-nspawn container scripts using zfs

collection of basic scripts to create and re-create containers

## features

- just systemd and zsh and zfs, does not even depend on ansible or install ssh
- uses zfs to snapshot
- uses zfs to save space using COW
- uses systemd
- just rsyncs your configs into container. You get a clear and easily maintainable filesystem tree of changes to be applied

## requirements

- zfs
- configure `include_config.sh`
- configure all config-files in `./container_configs` that will be rsynced into container

## usage

1. configure your config tree
1. create your base linux images  
  e.g. `./base-create_bullseye.sh`
1. create container based on linux image
  e.g. `./create_webentrance.sh`
1. add your own stuff, e.g. Let'sEncrypt

## updating containers

- what for? just throw them away and re-created them in an instance
- but you can also run `update.sh` if you want zero downtime or `machinectl shell <name>`

