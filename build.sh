#!/usr/bin/env bash
set -euo pipefail

# =======================
# Config (override via env)
# =======================
: "${MATRIX_GOOS:=linux darwin windows}"
: "${MATRIX_GOARCH:=amd64 arm64}"
: "${RELEASE_NAME_PREFIX:=sshpiper}"
: "${CGO_ENABLED_DEFAULT:=0}"
: "${SSHPIPER_REPO:=https://github.com/tg123/sshpiper}"
: "${REST_PLUGIN_REPO:=https://github.com/11notes/docker-sshpiper}"

ROOT="$(pwd)"
BUILD_DIR="${ROOT}/build"
SRC_DIR="${BUILD_DIR}/src"
OUT_DIR="${BUILD_DIR}/out"
STAGE_DIR="${BUILD_DIR}/stage"
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "[*] Clean build dir"
rm -rf "${BUILD_DIR}"
mkdir -p "${SRC_DIR}" "${OUT_DIR}" "${STAGE_DIR}"

# ----- Clone sshpiper and checkout the desired tag -----
echo "[*] Cloning sshpiper upstream…"
git -C "${SRC_DIR}" clone "${SSHPIPER_REPO}"

SSHPIPER_SRC="${SRC_DIR}/sshpiper"
pushd "${SSHPIPER_SRC}" >/dev/null
  # Determine VERSION:
  # 1) explicit VERSION env
  # 2) GitHub Actions ref (tag) like v1.5.0
  # 3) latest v* tag in repo
  git fetch --tags --force --prune >/dev/null 2>&1 || true
  VERSION="${VERSION:-${GITHUB_REF_NAME:-}}"
  if [[ -z "${VERSION}" ]]; then
    VERSION="$(git tag --list 'v*' --sort=-v:refname | head -n1 || true)"
  fi
  if [[ -z "${VERSION}" ]]; then
    echo "[!] No version tag found; defaulting to v0.0.0 (building current HEAD)"
    VERSION="v0.0.0"
  else
    echo "[*] Checking out tag ${VERSION}"
    git checkout -q "refs/tags/${VERSION}"
  fi

  # Submodules at this tag
  git submodule update --init --recursive
  GIT_SHA="$(git rev-parse --short HEAD || true)"
  echo "[*] Using VERSION=${VERSION} (commit ${GIT_SHA})"
popd >/dev/null

# ----- Clone REST plugin repo (third-party) -----
echo "[*] Cloning REST plugin repo…"
git -C "${SRC_DIR}" clone --depth 1 "${REST_PLUGIN_REPO}"
PLUGIN_ROOT="${SRC_DIR}/docker-sshpiper/build/plugin"

# The plugin repo isn’t a Go module at root; init per-plugin modules
prepare_plugin_mod () {
  local dir="$1" modname="$2"
  if [[ ! -f "${dir}/go.mod" ]]; then
    echo "[*] go mod init in ${dir} (${modname})"
    pushd "${dir}" >/dev/null
      go mod init "${modname}"
      go mod tidy
    popd >/dev/null
  fi
}
prepare_plugin_mod "${PLUGIN_ROOT}/rest_auth"      "github.com/11notes/rest_auth"
# If you ever want rest_challenge too, uncomment the next line:
# prepare_plugin_mod "${PLUGIN_ROOT}/rest_challenge" "github.com/11notes/rest_challenge"

# ----- Build one OS/arch tuple -----
build_target () {
  local goos="$1" goarch="$2"
  local cgo="${CGO_ENABLED_DEFAULT}"

  echo "[*] Building ${goos}/${goarch}"
  local ext=""
  if [[ "${goos}" == "windows" ]]; then ext=".exe"; fi

  local target_dir="${OUT_DIR}/${goos}-${goarch}"
  mkdir -p "${target_dir}"

  local ldflags="-s -w -X main.version=${VERSION} -X main.date=${DATE_UTC}"

  # sshpiperd (daemon) at the checked-out tag
  echo "    - sshpiperd"
  (
    cd "${SSHPIPER_SRC}"
    CGO_ENABLED="${cgo}" GOOS="${goos}" GOARCH="${goarch}" \
      go build -tags full -trimpath -ldflags "${ldflags}" \
      -o "${target_dir}/sshpiperd${ext}" ./cmd/sshpiperd
  )

  # rest_auth plugin → renamed to sshpiperd-rest
  echo "    - rest_auth → sshpiperd-rest"
  (
    cd "${PLUGIN_ROOT}/rest_auth"
    CGO_ENABLED="${cgo}" GOOS="${goos}" GOARCH="${goarch}" \
      go build -trimpath -ldflags "-s -w" \
      -o "${target_dir}/sshpiperd-rest${ext}" .
  )

  # Versioned package dir (matches README)
  local base="${RELEASE_NAME_PREFIX}-${VERSION}-${goos}-${goarch}"
  local pkg_dir="${STAGE_DIR}/${base}"
  rm -rf "${pkg_dir}"
  mkdir -p "${pkg_dir}"
  cp "${target_dir}/sshpiperd${ext}" "${pkg_dir}/"
  cp "${target_dir}/sshpiperd-rest${ext}" "${pkg_dir}/"

  # .tar.xz package
  local tarball="${OUT_DIR}/${base}.tar.xz"
  echo "    - packaging ${tarball}"
  ( cd "${STAGE_DIR}" && tar -cJf "${tarball}" "$(basename "${pkg_dir}")" )

  # checksum
  ( cd "${OUT_DIR}" && sha256sum "$(basename "${tarball}")" >> SHA256SUMS.txt )
}

# ----- Build matrix -----
: > "${OUT_DIR}/SHA256SUMS.txt"
for goos in ${MATRIX_GOOS}; do
  for goarch in ${MATRIX_GOARCH}; do
    build_target "${goos}" "${goarch}"
  done
done

echo "[*] Artifacts in ${OUT_DIR}:"
ls -lh "${OUT_DIR}"
echo "[*] Done."
