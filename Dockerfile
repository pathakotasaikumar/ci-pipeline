
FROM --platform=linux/amd64 centos:7 as runtime

ARG BUILD_DATE
ARG RUBY_VERSION

LABEL maintainer="QCP Team <cloud@qantas.com.au>" \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.title="qcp/pipeline" \
    org.opencontainers.image.author="QCP Team <cloud@qantas.com.au>" \
    org.opencontainers.image.description="Qantas Cloud Platform Pipeline is responsible for building, deploying and managing the lifecycle of the applications through a standardised and repeatable framework." \
    org.opencontainers.image.url="https://confluence.qantas.com.au/display/QOP/Using+Docker+container+for+local+development" \
    org.opencontainers.image.documentation="https://confluence.qantas.com.au/display/QOP/User+Guide" \
    org.opencontainers.image.source="https://github.com/qantas-cloud/c031-pipeline" \
    org.opencontainers.image.vendor="Qantas Group"

ENV BUILD_DIR /build-dir
COPY . ${BUILD_DIR}/pipeline
WORKDIR ${BUILD_DIR}/pipeline
ENTRYPOINT [ "sh", "-c", "${BUILD_DIR}/pipeline/entrypoint $0 $@" ]

RUN curl https://nexus.qcpaws.qantas.com.au/nexus/repository/qpkgs/umbrella/umbrella-root.pem -o /etc/pki/ca-trust/source/anchors/umbrella-root.pem \
	&& update-ca-trust

# base patches, tools and prereqs
RUN yum -y clean all \
    && yum -y update \
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
    && yum clean all

RUN useradd -m -u 501 qcp \
    &&  chown qcp:qcp /home/qcp/ \
    && echo '%wheel    ALL=(ALL)    NOPASSWD:ALL' > /etc/sudoers.d/wheel \
    && chmod 0440 /etc/sudoers.d/wheel

# Ruby install through rbenv
ENV PATH="/root/.rbenv/bin:${BUILD_DIR}/pipeline/bin:~/vendor/bin:${PATH}:/root/.rbenv/shims"
RUN sh -c 'curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash'
RUN /root/.rbenv/bin/rbenv install

# Bundle install
RUN ${BUILD_DIR}/pipeline/bin/pipeline_bundle.sh

# additional tooling - AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/var/tmp/awscliv2.zip" \
    && cd /var/tmp/ \
    && unzip awscliv2.zip \
    && sudo ./aws/install \
    && rm -f /var/tmp/awscliv2.zip

RUN sh -c 'aws --version'

# additional tooling - PowerShell to support *.ps scripts testing
RUN curl https://packages.microsoft.com/config/rhel/7/prod.repo \
    | sudo tee /etc/yum.repos.d/microsoft.repo \
    && yum install -y powershell \
    && yum clean all

# Latest Pester seems to fail, 4.4.1 looks stable
# https://github.com/pester/Pester/issues/1113
# always try to load module after install, check validity
RUN pwsh -c "Install-Module -Name Pester -RequiredVersion 4.4.1 -Force -SkipPublisherCheck" \
    && pwsh -c "Import-Module Pester" \
    && pwsh -c "Install-Module -Name AWSPowerShell -Force -SkipPublisherCheck" \
    && pwsh -c "Import-Module AWSPowerShell"

# post-setup callback for every container start
# generates default configs for saml_assume and pipeline itself
RUN mkdir -p /root/.aws \
    && touch /root/.bashrc \
    && echo "yes | cp -rf ${BUILD_DIR}/pipeline/bin/pipeline_local.sh /root/.pipeline \
    && source /root/.pipeline $USER_ID" \
    >> /root/.bashrc