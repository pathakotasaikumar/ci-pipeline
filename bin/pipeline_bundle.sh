#!/usr/bin/env bash
system_install=false
while getopts 's' flag; do
    case "${flag}" in
        s) system_install=true ;;
        *) exit 1 ;;
    esac
done

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

echo '[Pipeline bundle] - ruby versions'
which ruby && ruby --version
which gem && gem --version
which bundle

echo '[Pipeline bundle] - gem'
gem env
gem list

echo '[Pipeline bundle] - bundle install'
bundle env
bundle config
bundle install
cd -