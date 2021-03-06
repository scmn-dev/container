FROM ubuntu:18.04

ENV UPG="apt-get upgrade -y"
ENV UPD="apt-get update"
ENV INS="apt-get install"
ENV PKGS="zip unzip zsh git multitail sudo curl lsof wget ssl-cert asciidoctor apt-transport-https ca-certificates bash-completion pkg-config htop locales procps openssh-client dumb-init gnupg-agent bash-completion build-essential htop jq software-properties-common less llvm locales man-db nano vim ruby-full build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev libbz2-dev rsync libx11-dev libxkbfile-dev libsecret-1-dev systemd systemd-sysv"

USER root

RUN $UPD && $INS -y $PKGS && $UPD && $UPG && rm -rf /var/lib/apt/lists/*

RUN sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8

### create `coder` user ###
RUN adduser --gecos '' --disabled-password coder && \
  echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

### nodejs, npm and yarn ###
USER root
RUN curl -sL https://deb.nodesource.com/setup_16.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    $INS nodejs build-essential -y && \
    rm -rf nodesource_setup.sh && \
    $UPD

RUN npm i -g yarn

### install C/C++ compiler and associated tools ###
USER root
RUN $INS g++ gcc

### ruby ###
USER coder
RUN curl -fsSL https://rvm.io/mpapis.asc | gpg --import - \
    && curl -fsSL https://rvm.io/pkuczynski.asc | gpg --import - \
    && curl -fsSL https://get.rvm.io | bash -s stable \
    && bash -lc " \
        rvm requirements \
        && rvm install 2.7.3 \
        && rvm use 2.7.3 --default \
        && rvm rubygems current \
        && gem install bundler --no-document \
        && gem install solargraph --no-document" \
    && echo '[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*' >> /home/coder/.bashrc.d
RUN echo "rvm_gems_path=/home/coder/.rvm" > ~/.rvmrc
ENV GEM_HOME=/home/coder/.rvm
ENV GEM_PATH=$GEM_HOME:$GEM_PATH
ENV PATH=/home/coder/.rvm/bin:$PATH

### rust ###
WORKDIR /home/coder/
USER coder
RUN cp /home/coder/.profile /home/coder/.profile_orig && \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.55.0 \
    && .cargo/bin/rustup component add \
        rls \
        rust-analysis \
        rust-src \
        rustfmt \
    # && .cargo/bin/rustup completions bash | sudo tee /etc/bash_completion.d/rustup.bash-completion > /dev/null \
    # && .cargo/bin/rustup completions bash cargo | sudo tee /etc/bash_completion.d/rustup.cargo-bash-completion > /dev/null \
    && grep -v -F -x -f /home/coder/.profile_orig /home/coder/.profile > /home/coder/.bashrc.d
ENV PATH=$PATH:$HOME/.cargo/bin
# TODO: setting CARGO_HOME to /home/coder/.cargo avoids manual updates. Remove after full coder backups are GA.
ENV CARGO_HOME=/home/coder/.cargo
ENV PATH=$CARGO_HOME/bin:$PATH

RUN sudo mkdir -p $CARGO_HOME \
    && sudo chown -R coder:coder $CARGO_HOME

RUN bash -lc "cargo install cargo-watch cargo-edit cargo-tree cargo-workspaces"

# ### docker ###
USER root
ENV TRIGGER_REBUILD=3
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL https://get.docker.com -o get-docker.sh
RUN sh get-docker.sh

RUN curl -o /usr/bin/slirp4netns -fsSL https://github.com/rootless-containers/slirp4netns/releases/download/v1.1.12/slirp4netns-$(uname -m) \
    && chmod +x /usr/bin/slirp4netns

RUN curl -o /usr/local/bin/docker-compose -fsSL https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64 \
    && chmod +x /usr/local/bin/docker-compose

### docker:dive ###
RUN curl -o /tmp/dive.deb -fsSL https://github.com/wagoodman/dive/releases/download/v0.10.0/dive_0.10.0_linux_amd64.deb \
    && apt install /tmp/dive.deb \
    && rm /tmp/dive.deb

# enables docker starting with systemd
RUN systemctl enable docker

### zsh ###
USER coder
ENV src=".zshrc"
RUN sudo $INS zsh git -y
RUN zsh && \
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" && \
    sudo $UPD && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# modify ~/.zshrc
RUN sudo rm -rf $src
COPY $src .

### homebrew ###
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH /home/linuxbrew/.linuxbrew/bin:${PATH}

### golang ###
RUN brew install go

### install some usefull cli apps ###
###
# 1. GitHub CLI, https://github.com/cli/cli
# 2. GitLab CLI, https://github.com/profclems/glab
# 3. DigitalOcean CLI, https://github.com/digitalocean/doctl
# 4. Duf, https://github.com/muesli/duf
# 5. Secman, https://github.com/scmn-dev/secman
###

USER coder
RUN brew install gh glab doctl duf \
    && curl -fsSL https://unix.secman.dev | bash \
    && curl -fsSL https://code-server.dev/install.sh | sh
RUN wget https://raw.githubusercontent.com/cdr/code-server/main/ci/release-image/entrypoint.sh && sudo chmod 755 entrypoint.sh \
    && sudo mv entrypoint.sh /usr/bin/entrypoint.sh
RUN alias code="code-server"

### install fixuid ###
USER root
RUN ARCH="$(dpkg --print-architecture)" && \
    curl -fsSL "https://github.com/boxboat/fixuid/releases/download/v0.5/fixuid-0.5-linux-$ARCH.tar.gz" | tar -C /usr/local/bin -xzf - && \
    chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid && \
    mkdir -p /etc/fixuid && \
    printf "user: coder\ngroup: coder\n" > /etc/fixuid/config.yml

### micro cli editor ###
USER root
RUN curl https://getmic.ro | bash && \
    mv micro /usr/local/bin

EXPOSE 8080
# This way, if someone sets $DOCKER_USER, docker-exec will still work as
# the uid will remain the same. note: only relevant if -u isn't passed to
# docker-run.
USER 1000
ENV USER=coder
WORKDIR /home/coder
ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "."]

USER coder
