#!/usr/bin/env bash
# Copyright ©2022-2024 XSans0

# Function to show an informational message
err() {
    echo -e "\e[1;41$*\e[0m"
}

# Environment checker
echo "Checking environment ..."
for environment in TELEGRAM_TOKEN TELEGRAM_CHAT GIT_TOKEN BRANCH; do
    [ -z "${!environment}" ] && {
        err "- $environment not set!"
        exit 1
    }
done

# Get home directory
HOME_DIR="$(pwd)"

# Telegram setup
send_msg() {
    bash "$HOME_DIR/tg_utils.sh" msg ${@}
}
send_file() {
    bash "$HOME_DIR/tg_utils.sh" up "$1" "$2"
}

# Build LLVM
echo "building LLVM..."
send_msg "
╔ ⚒ =============<b>RastaMod69</b>============= ⚒ 
╠ <b>Start build RastaMod69 Clang</b> 
╠ LLVM Branch   : <code>[ $BRANCH ]</code> 
╠ Compiler      : <b>Github Actions</b>
╚ ⚒ ===================================== ⚒ "

./build-llvm.py \
    --defines LLVM_PARALLEL_COMPILE_JOBS="$(nproc)" LLVM_PARALLEL_LINK_JOBS="$(nproc)" CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3 \
    --install-folder "$HOME_DIR/install" \
    --no-update \
    --no-ccache \
    --quiet-cmake \
    --ref "$BRANCH" \
    --shallow-clone \
    --targets AArch64 ARM X86 \
    --vendor-string "RastaMod69"

# Check if the final clang binary exists or not
for file in install/bin/clang-[1-9]*; do
    if [ -e "$file" ]; then
        msg "LLVM build successful"
    else
        err "LLVM build failed!"
        send_msg "LLVM build failed!"
        exit
    fi
done

# Build binutils
echo "building binutils ..."
./build-binutils.py \
    --install-folder "$HOME_DIR/install" \
    --targets arm aarch64 x86_64

# Remove unused products
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strips remaining products
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    strip -s "${f::-1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    # Remove last character from file output (':')
    bin="${bin::-1}"

    echo "$bin"
    patchelf --set-rpath "$DIR/../lib" "$bin"
done

# Git config
git config --global user.name "Edwiin Kusuma Jaya"
git config --global user.email "kutemeikito0905@gmail.com"

# Get Clang Info
pushd "$HOME_DIR"/src/llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<<"$llvm_commit")"
popd || exit
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
clang_version="$("$HOME_DIR"/install/bin/clang --version | head -n1 | cut -d' ' -f4)"
build_date="$(TZ=Asia/Jakarta date +"%Y-%m-%d")"
tags="RastaMod69-Clang-$clang_version-release"
file="RastaMod69-Clang-$clang_version.tar.gz"
clang_link="https://git@github.com:kutemeikito/RastaMod69-Clang/releases/download/$tags/$file"

# Get binutils version
binutils_version=$(grep "LATEST_BINUTILS_RELEASE" build-binutils.py)
binutils_version=$(echo "$binutils_version" | grep -oP '\(\s*\K\d+,\s*\d+,\s*\d+' | tr -d ' ')
binutils_version=$(echo "$binutils_version" | tr ',' '.')

# Create simple info
pushd "$HOME_DIR"/install || exit
{
    echo "# Quick Info
* Build Date : $build_date
* Clang Version : $clang_version
* Binutils Version : $binutils_version
* Compiled Based : $llvm_commit_url"
} >>README.md
tar -czvf ../"$file" .
popd || exit

# Push
git clone "https://kutemeikito:$GIT_TOKEN@github.com/kutemeikito/RastaMod69-Clang.git" rel_repo
pushd rel_repo || exit
if [ -d "$BRANCH" ]; then
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
else
    mkdir -p "$BRANCH"
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
fi
git add .
git commit -asm "RastaMod69-Clang-$clang_version: $(TZ=Asia/Jakarta date +"%Y%m%d")"
git push -f origin main

# Check tags already exists or not
overwrite=y
git tag -l | grep "$tags" || overwrite=n
popd || exit

# Upload to github release
failed=n
if [ "$overwrite" == "y" ]; then
    ./github-release edit \
        --security-token "$GIT_TOKEN" \
        --user "kutemeikito" \
        --repo "RastaMod69-Clang" \
        --tag "$tags" \
        --description "$(cat "$HOME_DIR"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "kutemeikito" \
        --repo "RastaMod69-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$HOME_DIR/$file" \
        --replace || failed=y
else
    ./github-release release \
        --security-token "$GIT_TOKEN" \
        --user "kutemeikito" \
        --repo "RastaMod69-Clang" \
        --tag "$tags" \
        --description "$(cat "$HOME_DIR"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "kutemeikito" \
        --repo "RastaMod69-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$HOME_DIR/$file" || failed=y
fi

# Handle uploader if upload failed
while [ "$failed" == "y" ]; do
    failed=n
    msg "Upload again"
    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "kutemeikito" \
        --repo "RastaMod69-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$HOME_DIR/$file" \
        --replace || failed=y
done

# Send message to telegram
send_msg "
╔ ⛩ <b>=================Build Done!=================</b> ⛩
║
╠ 🗓 <b>Build Date : <code>$build_date</code></b> 
╠ ⚙️ <b>Clang Version : <code>$clang_version</code></b>
╠ 🖥 <b>Binutils Version : <code>$binutils_version</code></b>
╠ 🔗 <b>Compile Based : <a href='$llvm_commit_url'>Fork LLVM-Project</a></b> 
╠ 📍 <b>Push Repository : <a href='https://github.com/kutemeikito/RastaMod69-Clang.git'>RastaMod69-Clang</a></b>
╠ ⌚️ <b>Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !</b>
║
╚ ⛩ <b>============================================</b> ⛩"
