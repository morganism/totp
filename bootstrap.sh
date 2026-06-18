#!/usr/bin/env bash
: <<DOCXX
Running this after cloning will setup what this repo provides
The idea is each of my repos will have a bootstrap.sh file if appropriate.
https://raw.githubusercontent.com/morganism/totp/refs/heads/master/bootstrap.sh
Author: morgan@morganism.dev
Date: Thu 18 Jun 2026 07:26:43 BST
DOCXX

#---- for x-repo bootstrapping if implemented
#     hopes to solve dependency issues
declare -a MISSING_REPOS
declare -a MISSING_MESSAGES
if [[ -f ~/.ansi.functions ]]; then
  . ~/.ansi.functions                                  # created by the linker in tools 
else
  MISSING_REPOS+="tools"
  MISSING_MESSAGES+="Install Tools Repo for dotfiles"
fi

echo -e "🧚 ${Grey_8}Linking files ...${Reset}"

THIS=$(realpath $0)
THIS_DIR=$(dirname $THIS)
FILES_TO_LINK=$(find $THIS_DIR/bin -type f -exec realpath {} \;)

for f in "$FILES_TO_LINK"
do
  BN=$(basename $f)
  printf "${Grey_8}Linking ${White}%s${Reset}\n" "${BN}"
  ln -fs $f ~/bin/$BN
done

printf "${Green}%s${Reset}\n" "OK"


