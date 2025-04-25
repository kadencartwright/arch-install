#! /bin/env sh
CODE_DIR=$HOME/code
mkdir -p $CODE_DIR 
cd $CODE_DIR 
git clone https://github.com/kadencartwright/dotfiles
git clone https://github.com/kadencartwright/dotman

cd dotman
make

cd $CODE_DIR/dotfiles

../dotman/bin/dotman link -f ./dotman.toml
