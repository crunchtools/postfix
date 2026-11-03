FROM registry.access.redhat.com/ubi10/ubi-minimal:latest

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="UBI 10 Postfix SMTP router with opendkim signing. Accepts inbound mail on :25, signs outbound mail for the configured domains, and relays by recipient domain to backend mail containers."
LABEL org.opencontainers.image.source="https://github.com/crunchtools/postfix"
LABEL org.opencontainers.image.description="UBI 10 Postfix SMTP router with DKIM signing for crunchtools backend domains"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"

# postfix lives in ubi-10-appstream-rpms — no RHSM registration required.
# opendkim is not in any UBI 10 repo (BaseOS, AppStream or CodeReady); EPEL 10
# is the only source. Each install is its own command in the && chain so a
# failed one (e.g. an EPEL mirror outage) fails the build instead of shipping
# an image with no signer — see the container-image profile, 2026-10-22.
RUN curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10 https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-10 && \
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10 && \
    curl -fsSLo /tmp/epel-release.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm && \
    rpm -i /tmp/epel-release.rpm && \
    rm -f /tmp/epel-release.rpm && \
    microdnf install -y postfix && \
    microdnf install -y opendkim opendkim-tools && \
    microdnf clean all

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 25
ENTRYPOINT ["/entrypoint.sh"]
