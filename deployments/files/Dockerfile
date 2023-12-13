
FROM nexus.qcpaws.qantas.com.au:9443/verified/centos:7

ARG BUILD_DATE
ARG PROXY_PASSWORD
ARG RBENV_VERSION

LABEL maintainer="QCP Team <cloud@qantas.com.au>" \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.title="qcp/pipeline" \
    org.opencontainers.image.author="QCP Team <cloud@qantas.com.au>" \
    org.opencontainers.image.description="Qantas Cloud Platform Pipeline is responsible for building, deploying and managing the lifecycle of the applications through a standardised and repeatable framework." \
    org.opencontainers.image.url="https://confluence.qantas.com.au/display/QOP/Using+Docker+container+for+local+development" \
    org.opencontainers.image.documentation="https://confluence.qantas.com.au/display/QOP/User+Guide" \
    org.opencontainers.image.source="https://github.com/qantas-cloud/c031-pipeline" \
    org.opencontainers.image.vendor="Qantas Group"

ENV http_proxy="http://SVCP-AMS01-C031-01:$PROXY_PASSWORD@proxy.qcpaws.qantas.com.au:3128" \
    https_proxy="http://SVCP-AMS01-C031-01:$PROXY_PASSWORD@proxy.qcpaws.qantas.com.au:3128" \
    HTTP_PROXY="http://SVCP-AMS01-C031-01:$PROXY_PASSWORD@proxy.qcpaws.qantas.com.au:3128" \
    HTTPS_PROXY="http://SVCP-AMS01-C031-01:$PROXY_PASSWORD@proxy.qcpaws.qantas.com.au:3128" \
    no_proxy='127.0.0.1,169.254.169.254,localhost.localdomain,localhost,.qcpaws.qantas.com.au,s3-ap-southeast-2.amazonaws.com,.v,s3.ap-southeast-2.amazonaws.com,.s3.ap-southeast-2.amazonaws.com,.aws.qcp,dynamodb.ap-southeast-2.amazonaws.com,.dynamodb.ap-southeast-2.amazonaws.com,logs.ap-southeast-2.amazonaws.com,.ap-southeast-2.opsworks-cm.io' \
    BUILD_DIR='/build-dir'

COPY . ${BUILD_DIR}/pipeline
WORKDIR ${BUILD_DIR}/pipeline
ENTRYPOINT [ "sh", "-c", "${BUILD_DIR}/pipeline/entrypoint $0 $@" ]

# base patches, tools and prereqs
RUN sed -i 's/#baseurl/baseurl/g' /etc/yum.repos.d/CentOS-Base.repo && sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-Base.repo \
    && yum -y localinstall https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm \
    && yum clean all \
    && sed -i 's/^metalink/#metalink/' /etc/yum.repos.d/epel.repo \
    && sed -i 's/^#baseurl/baseurl/' /etc/yum.repos.d/epel.repo \
    && sed -i 's/download.fedoraproject/dl.fedoraproject/' /etc/yum.repos.d/epel.repo

RUN yum -y update \
    && yum -y install \
    which \
    git \
    curl \
    sudo \
    zip \
    unzip \
    wget \
    bind-utils \
    autoconf \
    automake \
    bison \
    bzip2 \
    gcc-c++ \
    libffi-devel \
    libtool \
    make \
    patch \
    readline-devel \
    sqlite-devel \
    zlib-devel \
    glibc-headers \
    glibc-devel \
    libyaml-devel \
    openssl-devel \
    python-devel \
    python-pip \
    python34 \
    python34-devel \
    krb5-workstation \
    requirements_centos_libs_install \
    && yum clean all

RUN useradd -m -u 501 qcp \
    &&  chown qcp:qcp /home/qcp/ \
    && echo '%wheel    ALL=(ALL)    NOPASSWD:ALL' > /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel

# Ruby install through rbenv
ENV PATH="${BUILD_DIR}/pipeline/bin:~/vendor/bin:~/.rbenv/bin:~/.rbenv/shims:/root/.rbenv/shims:${PATH}"
RUN sh -c 'curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-installer | bash'
RUN rbenv install ${RBENV_VERSION}
RUN rbenv global ${RBENV_VERSION}

# additional tooling - AWS CLI
RUN curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "/var/tmp/awscli-bundle.zip" \
    && unzip /var/tmp/awscli-bundle.zip -d /var/tmp/ \
    && /var/tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws \
    && rm -f /var/tmp/awscli-bundle.zip \
    && rm -rf /var/tmp/awscli-bundle

# post-setup callback for every container start
# generates default configs for saml_assume and pipeline itself
RUN mkdir -p /root/.aws \
    && touch /root/.bashrc \
    && echo "yes | cp -rf ${BUILD_DIR}/pipeline/deployments/scripts/environment-configuration.sh /root/.pipeline \
    && source /root/.pipeline" \
    >> /root/.bashrc

# configures keytab to allow pipeline to create DNS records in .qcpaws.qantas.com.au
RUN mkdir -p /data/bambooagent \
    && mv ${BUILD_DIR}/pipeline/deployments/files/dns-qcpaws.keytab /data/bambooagent/ \
    && chmod 755 /data/bambooagent/dns-qcpaws.keytab \
    && sed -i '/default_ccache_name/d' /etc/krb5.conf

# unsetting proxy to allow for successful codebuild checkin
ENV http_proxy='' \
    https_proxy='' \
    HTTP_PROXY='' \
    HTTPS_PROXY='' \
    no_proxy=''
