FROM debian:latest
FROM codercom/code-server:3.12.0

ARG UPD="apt-get update"
ARG INS="apt-get install"
ENV PKGS="zip unzip multitail curl lsof wget ssl-cert asciidoctor apt-transport-https ca-certificates gnupg-agent bash-completion build-essential htop jq software-properties-common less llvm locales man-db nano vim ruby-full"
ENV BUILDS="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev libbz2-dev"

USER root

RUN $UPD && $INS -y $PKGS && $UPD && \
    locale-gen en_US.UTF-8 && \
    mkdir /var/lib/apt/abdcodedoc-marks && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* && \
    $UPD

ENV LANG=en_US.UTF-8

### nodejs & npm ###
USER root
RUN curl -sL https://deb.nodesource.com/setup_16.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    $INS nodejs build-essential -y && \
    rm -rf nodesource_setup.sh && \
    $UPD

### install C/C++ compiler and associated tools ###
USER root
RUN $INS g++

### go ###
USER coder
ENV GO_VERSION=1.17.2
ENV GOPATH=$HOME/go-packages
ENV GOROOT=$HOME/go
ENV PATH=$GOROOT/bin:$GOPATH/bin:$PATH
RUN curl -fsSL https://storage.googleapis.com/golang/go$GO_VERSION.linux-amd64.tar.gz | tar xzs && \
# install VS Code Go tools for use with gopls as per https://github.com/golang/vscode-go/blob/master/docs/tools.md
# also https://github.com/golang/vscode-go/blob/27bbf42a1523cadb19fad21e0f9d7c316b625684/src/goTools.ts#L139
    go get -v \
        github.com/uudashr/gopkgs/cmd/gopkgs@v2 \
        github.com/ramya-rao-a/go-outline \
        github.com/cweill/gotests/gotests \
        github.com/fatih/gomodifytags \
        github.com/josharian/impl \
        github.com/haya14busa/goplay/cmd/goplay \
        github.com/go-delve/delve/cmd/dlv \
        github.com/golangci/golangci-lint/cmd/golangci-lint && \
    GO111MODULE=on go get -v \
        golang.org/x/tools/gopls@v0.7.2 && \
    sudo rm -rf $GOPATH/src $GOPATH/pkg /home/coder/.cache/go /home/coder/.cache/go-build
# user Go packages
ENV GOPATH=/home/coder/go
ENV PATH=/home/coder/go/bin:$PATH

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
USER coder
RUN cp /home/coder/.profile /home/coder/.profile_orig && \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.55.0 \
    && .cargo/bin/rustup component add \
        rls \
        rust-analysis \
        rust-src \
        rustfmt \
    && .cargo/bin/rustup completions bash | sudo tee /etc/bash_completion.d/rustup.bash-completion > /dev/null \
    && .cargo/bin/rustup completions bash cargo | sudo tee /etc/bash_completion.d/rustup.cargo-bash-completion > /dev/null \
    && grep -v -F -x -f /home/coder/.profile_orig /home/coder/.profile > /home/coder/.bashrc.d
ENV PATH=$PATH:$HOME/.cargo/bin
# TODO: setting CARGO_HOME to /home/coder/.cargo avoids manual updates. Remove after full coder backups are GA.
ENV CARGO_HOME=/home/coder/.cargo
ENV PATH=$CARGO_HOME/bin:$PATH

RUN sudo mkdir -p $CARGO_HOME \
    && sudo chown -R coder:coder $CARGO_HOME

RUN bash -lc "cargo install cargo-watch cargo-edit cargo-tree cargo-workspaces"

### docker ###
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

### secman ###
RUN curl -fsSL https://unix.secman.dev | bash

### zsh ###
USER root
ENV src=".zshrc"
RUN $INS zsh -y
RUN zsh && \
    sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" && \
    $UPD && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

### rm old ~/.zshrc ###
RUN sudo rm -rf $src

### wget new files ###
COPY $src .

### homebrew ###
USER coder
ENV TRIGGER_BREW_REBUILD=4
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH=$PATH:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin/
ENV MANPATH="$MANPATH:/home/linuxbrew/.linuxbrew/share/man"
ENV INFOPATH="$INFOPATH:/home/linuxbrew/.linuxbrew/share/info"
ENV HOMEBREW_NO_AUTO_UPDATE=1

### github cli ###
USER coder
RUN brew install gh

### micro cli editor ###
USER root
RUN curl https://getmic.ro | bash && \
    mv micro /usr/local/bin

USER coder
