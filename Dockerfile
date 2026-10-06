# Builds netatalk 4.6.1 from source with ACL support enabled, then applies the
# volume-table patch (see env_setup.sh) on top of the upstream entrypoint.
#
# Why a source build rather than an overlay on netatalk/netatalk: the published
# image is compiled with -Dwith-acls=false, so netatalk computes a volume's
# visibility from raw POSIX mode bits and ignores filesystem ACLs entirely. On a
# read-only mount the share directory cannot be chowned, so its ACLs never take
# effect and the volume is dropped from the server's volume list. Enabling ACLs
# makes netatalk honour the filesystem ACLs (e.g. ZFS NFSv4 ACLs) instead.
#
# Base is pinned to the same distro and dependency set as the upstream
# Dockerfile so the only intentional differences are ACLs and env_setup.sh.

# Pinned upstream release; bump deliberately.
ARG NETATALK_VERSION=4.6.1

# Dependency lists are declared before the first FROM so both the build and the
# deploy stage can use them (a global ARG is required for a later stage to
# receive the value).
ARG RUN_DEPS="\
    avahi \
    cups \
    db \
    dbus \
    glib \
    iniparser \
    krb5 \
    libevent \
    libgcrypt \
    libunwind \
    linux-pam \
    mariadb-client \
    mariadb-connector-c \
    openldap \
    sqlite \
    talloc \
    tzdata \
    acl \
    "
ARG BUILD_DEPS="\
    avahi-dev \
    cups-dev \
    db-dev \
    dbus-dev \
    build-base \
    gcc \
    iniparser-dev \
    krb5-dev \
    libevent-dev \
    libgcrypt-dev \
    libunwind-dev \
    linux-pam-dev \
    mariadb-dev \
    meson \
    ninja \
    openldap-dev \
    pkgconfig \
    sqlite-dev \
    talloc-dev \
    acl-dev \
    curl \
    tar \
    "

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS build

ARG NETATALK_VERSION
ARG RUN_DEPS
ARG BUILD_DEPS
ENV RUN_DEPS=$RUN_DEPS
ENV BUILD_DEPS=$BUILD_DEPS

RUN apk add --no-cache $RUN_DEPS $BUILD_DEPS

WORKDIR /netatalk-code
RUN curl -sSL "https://github.com/Netatalk/netatalk/archive/refs/tags/netatalk-${NETATALK_VERSION//./-}.tar.gz" \
    | tar xz --strip-components=1

RUN meson setup build \
    -Dbuildtype=release \
    -Dwith-acls=true \
    -Dwith-appletalk=true \
    -Dwith-cnid-backends=dbd,mysql,sqlite \
    -Dwith-docs= \
    -Dwith-dtrace=false \
    -Dwith-init-style=none \
    -Dwith-pkgconfdir-path=/etc/netatalk \
    -Dwith-quota=false \
    -Dwith-fce=false \
    -Dwith-spotlight=true \
    -Dwith-tcp-wrappers=false \
    -Dwith-tests=false \
    -Dwith-testsuite=false \
&&  meson compile -C build \
&&  meson install --destdir=/staging/ -C build

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS deploy

ARG RUN_DEPS
ENV RUN_DEPS=$RUN_DEPS

COPY --from=build /staging/ /
COPY --from=build /netatalk-code/distrib/docker/config_watch.sh /config_watch.sh

RUN apk add --no-cache $RUN_DEPS \
&&  ln -sf /dev/stdout /var/log/afpd.log

COPY env_setup.sh /env_setup.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /env_setup.sh /entrypoint.sh

WORKDIR /mnt
EXPOSE 548
VOLUME ["/mnt/afpshare", "/mnt/afpbackup"]
CMD ["/entrypoint.sh"]
