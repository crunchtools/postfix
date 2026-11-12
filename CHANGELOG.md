# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.1] - 2026-11-11

### Fixed
- The image boots on RHEL 10.3's postfix 3.8.5-11, which ships its spool as
  tmpfiles.d entries rather than directories. The build now creates them, so
  postfix no longer dies with `chdir(/var/spool/postfix)`.

### Added
- DKIM signing. An `opendkim` milter runs alongside postfix and signs outbound
  mail for the configured domains, so our notification mail is no longer
  SPF-only (RT#1548). The signer is optional — with no `/conf/opendkim.conf`
  mounted the image is the plain relay it was before — but mandatory once
  configured: if it will not start, the container does not start.
- Five new mounts for the signer: `opendkim.conf`, `keytable`, `signingtable`,
  `internalhosts`, and the read-only `dkim/` key directory.
- `test/boot-test.sh`, a boot test that starts the image as production starts
  it and asserts postfix answers on `:25`, opendkim is up, mail from a listed
  client for a listed domain is signed, and mail is *not* signed when either
  the signing table or `InternalHosts` says no. CI runs it before pushing.
- Weekly scheduled rebuild, to pick up base image and EPEL security updates
  between commits.

### Changed
- The build adds EPEL 10 (GPG key imported first, so packages are verified).
  `opendkim` is in no UBI 10 repository, so this is the only source for it.
- Constitution is now a v1.18.0 manifest: fleet and profile rules apply by
  reference, and only this repo's specifics are kept.
- Constitution validation is pinned via `constitution.yml`.
- Dependabot auto-merges GitHub Actions minor and patch updates.

## [1.0.0] - 2026-09-20

First tagged release. This image has been running in production since before
it had version control; this release marks the current state as the baseline
going forward.
