set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

vm-test:
    scripts/vm-qemu-test.sh test

vm-test-full:
    scripts/vm-qemu-test.sh test --full

vm-build-iso:
    scripts/vm-qemu-test.sh build-iso

vm-install:
    scripts/vm-qemu-test.sh install

vm-boot-check:
    scripts/vm-qemu-test.sh boot-check

vm-clean:
    scripts/vm-qemu-test.sh clean
