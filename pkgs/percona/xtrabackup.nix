{ stdenv, fetchurl, pkgs, boost, percona, ... }:

stdenv.mkDerivation rec {
  name = "xtrabackup-${version}";
  version = "8.0.7";

  src = fetchurl {
    url = "https://www.percona.com/downloads/Percona-XtraBackup-8.0/Percona-XtraBackup-${version}/source/tarball/percona-xtrabackup-${version}.tar.gz";
    sha256 = "1qiwynlrs63fwbrmrl6gv5q86zyh5fgyv6w0vjnahwry18gnjk52";
  };

  buildInputs = with pkgs; [
    bison
    boost
    cmake
    curl
    libaio
    libev
    libgcrypt
    libgpgerror
    ncurses
    percona
    vim
  ];

  enableParallelBuilding = true;
  cmakeFlags = [
    "-DBUILD_CONFIG=xtrabackup_release"
    "-DGCRYPT_LIB_PATH=${pkgs.libgcrypt}/lib:${pkgs.libgpgerror}/lib"
    "-DWITH_MAN_PAGES=OFF"
  ];

  prePatch = ''
    # Disable ABI check. See case #108154
    sed -i "s/SET(RUN_ABI_CHECK 1)/SET(RUN_ABI_CHECK 0)/" cmake/abi_check.cmake

  '';

  preBuild = ''
    export LD_LIBRARY_PATH=$(pwd)/library_output_directory
  '';

  postInstall = ''
    chmod g-w $out
  '';

  meta = {
    homepage = https://www.percona.com/;
    description = "Percona XtraBackup";
  };
}
