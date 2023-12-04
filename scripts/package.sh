#!/usr/bin/env sh
#
# Distribute Bootware in package formats.

# Exit immediately if a command exits or pipes a non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command pipeline fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

#######################################
# Show CLI help information.
# Cannot use function name help, since help is a pre-existing command.
# Outputs:
#   Writes help information to stdout.
#######################################
usage() {
  cat 1>&2 << EOF
Distribute Bootware in package formats.

Usage: package [OPTIONS] [SUBCOMMAND] PACKAGES

Options:
      --debug               Enable shell debug traces
  -h, --help                Print help information
  -v, --version <VERSION>   Version of Bootware package

Subcommands:
  ansible   Build Bootware Ansible collection
  build     Build Bootware packages
  dist      Build Bootware packages for distribution
  test      Run Bootware package tests in Docker
EOF
}

#######################################
# Build Ansible Galaxy collection.
#######################################
ansible_() {
  filename="scruffaluff-bootware-${1}.tar.gz"
  mkdir -p dist

  cp CHANGELOG.md README.md ansible_collections/scruffaluff/bootware/
  poetry run ansible-galaxy collection build --force --output-path dist \
    ansible_collections/scruffaluff/bootware
  checksum "dist/${filename}"
}

#######################################
# Build an Alpine package.
#######################################
apk() {
  export version="${1}"
  build="$(mktemp --directory)"

  mkdir -p dist
  abuild-keygen -n --append --install

  cp completions/bootware.bash completions/bootware.fish "${build}/"
  cp completions/bootware.man "${build}/bootware.1"
  cp bootware.sh "${build}/bootware"

  # Single quotes around variable is intentional to inform envsubst which
  # patterns to replace in the template.
  # shellcheck disable=SC2016
  envsubst '${version}' < scripts/templates/APKBUILD.tmpl > "${build}/APKBUILD"

  cd "${build}"
  abuild checksum
  abuild -r

  mv "${HOME}/packages/tmp/$(uname -m)/bootware-${version}-r0.apk" dist/
  checksum "dist/bootware-${version}-r0.apk"
}

#######################################
# Build subcommand.
#######################################
build() {
  version="${1}"
  shift 1

  for package in "$@"; do
    case "${package}" in
      apk)
        apk "${version}"
        ;;
      deb)
        deb "${version}"
        ;;
      rpm)
        rpm "${version}"
        ;;
      *)
        echo "error: Unsupported package type '${package}'."
        exit 2
        ;;
    esac
  done
}

#######################################
# Compute checksum for file.
#######################################
checksum() {
  folder="$(dirname "${1}")"
  file="$(basename "${1}")"
  (cd "${folder}" && shasum --algorithm 512 "${file}" > "${file}.sha512")
}

#######################################
# Build a Debian package.
#
# For a tutorial on building an DEB package, visit
# https://www.debian.org/doc/manuals/debian-faq/pkg-basics.en.html.
#######################################
deb() {
  export version="${1}"
  build="$(mktemp --directory)"

  mkdir -p "${build}/DEBIAN" "${build}/etc/bash_completion.d" \
    "${build}/etc/fish/completions" "${build}/usr/local/bin" \
    "${build}/usr/local/share/man/man1" dist

  cp completions/bootware.bash "${build}/etc/bash_completion.d/"
  cp completions/bootware.fish "${build}/etc/fish/completions/"
  cp completions/bootware.man "${build}/usr/local/share/man/man1/bootware.1"
  cp bootware.sh "${build}/usr/local/bin/bootware"

  envsubst < scripts/templates/control.tmpl > "${build}/DEBIAN/control"
  dpkg-deb --build "${build}" "dist/bootware_${version}_all.deb"
  checksum "dist/bootware_${version}_all.deb"
}

#######################################
# Dist subcommand.
#######################################
dist() {
  version="${1}"
  shift 1

  for package in "$@"; do
    docker build --build-arg "version=${version}" \
      --file "tests/integration/${package}.dockerfile" \
      --output dist --target dist .
  done
}

#######################################
# Build a RPM package.
#
# For a tutorial on building an RPM package, visit
# https://rpm-packaging-guide.github.io/#packaging-software.
#######################################
rpm() {
  export version="${1}"
  build="${HOME}/rpmbuild"
  tmp_dir="$(mktemp --directory)"
  archive_dir="${tmp_dir}/bootware-${version}"

  mkdir -p "${archive_dir}" "${build}/SOURCES" "${build}/SPECS" dist

  cp completions/bootware.bash completions/bootware.fish "${archive_dir}/"
  cp completions/bootware.man "${archive_dir}/bootware.1"
  cp bootware.sh "${archive_dir}/bootware"
  tar czf "bootware-${version}.tar.gz" -C "${tmp_dir}" .
  mv "bootware-${version}.tar.gz" "${build}/SOURCES/"

  envsubst < scripts/templates/bootware.spec.tmpl > "${build}/SPECS/bootware.spec"
  rpmbuild -ba "${build}/SPECS/bootware.spec"
  mv "${build}/RPMS/noarch/bootware-${version}-1.fc33.noarch.rpm" dist/
  checksum "dist/bootware-${version}-1.fc33.noarch.rpm"
  rm -fr "${build}" "${tmp_dir}"
}

#######################################
# Test subcommand.
#######################################
test() {
  version="${1}"
  shift 1

  for package in "$@"; do
    docker build --build-arg "version=${version}" \
      --file "tests/integration/${package}.dockerfile" \
      --tag "scruffaluff/bootware:${package}" .
  done
}

#######################################
# Script entrypoint.
#######################################
main() {
  version='0.7.3'

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -v | --version)
        version="${2}"
        shift 2
        ;;
      ansible)
        shift 1
        ansible_ "${version}" "$@"
        exit 0
        ;;
      build)
        shift 1
        build "${version}" "$@"
        exit 0
        ;;
      dist)
        shift 1
        dist "${version}" "$@"
        exit 0
        ;;
      test)
        shift 1
        test "${version}" "$@"
        exit 0
        ;;
      *)
        echo "error: No such subcommand or option '${1}'"
        exit 2
        ;;
    esac
  done

  usage
}

main "$@"
