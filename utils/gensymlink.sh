#!/usr/bin/env bash

find . -name "*.sh" -not -path "./utils/*"| while read -r file; do 
    src="${PWD}/${file}"
    dst=./bin/"$(basename "${file}" .sh)"
    
    if [ ! -f "${dst}" ]; then
        ln -s "${src}" "${dst}"
        echo "Symlink created: ${dst}"
    fi
done

echo

declare -A RC_FILES=( ["BASH"]=".bashrc" ["ZSH"]=".zshrc")

if [[ ! "$PATH" == *"${PWD}/bin"* ]]; then
    for key in "${!RC_FILES[@]}"; do
    echo "${key}"
    echo "Add ${PWD}/bin to PATH in ${RC_FILES[${key}]} running:"
    echo "echo 'export PATH=\$PATH:${PWD}/bin' >> $HOME/${RC_FILES[${key}]}"
    echo "Then restart your terminal or run:"
    echo "source $HOME/${RC_FILES[${key}]}"
    echo 
done
fi

