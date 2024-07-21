#!/bin/bash

if ! command -v git &> /dev/null
then
    echo "git is not installed."
    echo "Please install with 'emerge --ask dev-vcs/git'."
    exit 1
fi

rm -rf /root/.pyenv
git clone https://github.com/pyenv/pyenv.git /root/.pyenv

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /root/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.bashrc
echo 'eval "$(pyenv init -)"' >> /root/.bashrc

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /root/.profile
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.profile
echo 'eval "$(pyenv init -)"' >> /root/.profile

source /root/.bashrc

pyenv install 3.10
pyenv global 3.10
