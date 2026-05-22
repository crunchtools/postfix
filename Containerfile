FROM registry.access.redhat.com/ubi10/ubi-minimal:latest

LABEL maintainer="fatherlinux <scott.mccarty@crunchtools.com>"
LABEL description="UBI 10 Postfix SMTP router. Accepts inbound mail on :25 and relays by recipient domain to backend mail containers."
LABEL org.opencontainers.image.source="https://github.com/crunchtools/postfix"
LABEL org.opencontainers.image.description="UBI 10 Postfix SMTP router for crunchtools backend domains"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"

# postfix lives in ubi-10-appstream-rpms — no RHSM registration required.
RUN microdnf install -y postfix && microdnf clean all

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 25
ENTRYPOINT ["/entrypoint.sh"]
