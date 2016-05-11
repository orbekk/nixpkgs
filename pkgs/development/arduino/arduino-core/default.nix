{ stdenv, fetchFromGitHub, fetchurl, jdk, jre, ant, coreutils, gnugrep, file,
libusb , unzip, zlib, readline, ncurses, withGui ? false, gtk2 ? null }:

assert withGui -> gtk2 != null;

let resources = [
  (rec {
    name = "reference-1.6.6-3.zip";
    url = "http://downloads.arduino.cc/${name}";
    sha256 = "119nj1idz85l71fy6a6wwsx0mcd8y0ib1wy0l6j9kz88nkwvggy3";
  })
  (rec {
    name = "Galileo_help_files-1.6.2.zip";
    url = "http://downloads.arduino.cc/${name}";
    sha256 = "0qda0xml353sfhjmx9my4mlcyzbf531k40dcr1cnsa438xp2fw0w";
  })
  (rec {
    name = "Edison_help_files-1.6.2.zip";
    url = "http://downloads.arduino.cc/${name}";
    sha256 = "1x25rivmh0zpa6lr8dafyxvim34wl3wnz3r9msfxg45hnbjqqwan";
  })
  (rec {
    name = "Firmata";
    tag = "2.4.4";
    url = "https://github.com/arduino-libraries/${name}/archive/v${tag}.zip";
    sha256 = "083p0zhwz519fhg5y4nzsb2fpsx3vpbg318x3vi6zl31wm1jp2k1";
  })
  (rec {
    name = "Bridge";
    tag = "1.1.0";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "1kmam0wzbjsi1hyxdffjqcc43ir7aipli2gd6z4mfm4ykcbhc606";
  })
  (rec {
    name = "Robot_Control";
    tag = "1.0.2";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "1wdpz3ilnza3lfd5a628dryic46j72h4a89y8vp0qkbscvifcvdk";
  })
  (rec {
    name = "Robot_Motor";
    tag = "1.0.2";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "0da21kfzy07kk2qnkprs3lj214fgkcjxlkk3hdp306jfv8ilmvy2";
  })
  (rec {
    name = "RobotIRremote";
    tag = "1.0.2";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "0wkya7dy4x0xyi7wn5aghmr1gj0d0wszd61pq18zgfdspz1gi6xn";
  })
  (rec {
    name = "SpacebrewYun";
    tag = "1.0.0";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "1sklyp92m8i31rfb9b9iw0zvvab1zd7jdmg85fr908xn6k05qhmp";
  })
  (rec {
    name = "Temboo";
    tag = "1.1.4";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "0cmi07s9n7m46d2pdhmcsww1byby2jjdww9wr8kbp7m41m345rhs";
  })
  (rec {
    name = "Esplora";
    tag = "1.0.4";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "1dflfrg38f0312nxn6wkkgq1ql4hx3y9kplalix6mkqmzwrdvna4";
  })
  (rec {
    name = "Mouse";
    tag = "1.0.0";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "0p3f3vhn15jxa7jrd8yrrmlqkn8j45z2qasnsnn6sd5n81xf6sqj";
  })
  (rec {
    name = "Keyboard";
    tag = "1.0.0";
    url = "https://github.com/arduino-libraries/${name}/archive/${tag}.zip";
    sha256 = "0zsr4wr14hmlvc2qmybv167h7r986xhsys1yn59f42j72md9l6ql";
  })
]; in stdenv.mkDerivation rec {

  version = "1.6.6";
  name = "arduino${stdenv.lib.optionalString (withGui == false) "-core"}-${version}";

  src = fetchFromGitHub {
    owner = "arduino";
    repo = "Arduino";
    rev = "${version}";
    sha256 = "1gm3sjjs149r2d82ynx25qlg31bbird1zr4x01qi4ybk3gp0268v";
  };

  buildInputs = [ jdk ant file unzip ];

  
  postUnpack = let getResource = { name, version, url, sha256, ... }: [(
    let file = fetchurl { inherit url sha256; }; in ''
      echo Fetching ${url}
      ln -s ${file} $sourceRoot/build/${name}-${tag}.zip
      ln -s ${file} $sourceRoot/build/shared/${name}
    '')]; in
    stdenv.lib.concatMap getResource resources;

  buildPhase = ''
    cd ./arduino-core && ant 
    cd ../build && ant 
    cd ..
  '';

  libPath = stdenv.lib.makeLibraryPath (builtins.filter (l: l != null) [
    gtk2 stdenv.cc.cc zlib readline libusb ncurses]) + ":$out/lib";

  installPhase = ''
    mkdir -p $out/share/arduino
    cp -r ./build/linux/work/* "$out/share/arduino/"
    echo ${version} > $out/share/arduino/lib/version.txt

    # Hack around lack of libtinfo in NixOS
    mkdir -p $out/lib
    ln -s ${ncurses.out}/lib/libncursesw.so.5 $out/lib/libtinfo.so.5

    ${stdenv.lib.optionalString withGui ''
      mkdir -p "$out/bin"
      sed -i -e "s|^JAVA=.*|JAVA=${jdk}/bin/java|" "$out/share/arduino/arduino"
      sed -i -e "s|^LD_LIBRARY_PATH=|LD_LIBRARY_PATH=${libPath}:|" "$out/share/arduino/arduino"
      ln -sr "$out/share/arduino/arduino" "$out/bin/arduino"
    ''}

    # Fixup "/lib64/ld-linux-x86-64.so.2" like references in ELF executables.
    echo "running patchelf on prebuilt binaries:"
    find "$out" | while read filepath; do
        if file "$filepath" | grep -q "ELF.*executable.*dynamic"; then
            # skip target firmware files
            if echo "$filepath" | grep -q "\.elf$"; then
                continue
            fi
            echo "setting interpreter $(cat "$NIX_CC"/nix-support/dynamic-linker) in $filepath"
            patchelf --set-interpreter "$(cat "$NIX_CC"/nix-support/dynamic-linker)" "$filepath"
            test $? -eq 0 || { echo "patchelf failed to process $filepath"; exit 1; }
        fi
    done

    patchelf --set-rpath ${libPath} \
        "$out/share/arduino/hardware/tools/avr/bin/avrdude_bin"
  '';

  meta = with stdenv.lib; {
    description = "Open-source electronics prototyping platform";
    homepage = http://arduino.cc/;
    license = stdenv.lib.licenses.gpl2;
    platforms = platforms.all;
    maintainers = with maintainers; [ antono robberer bjornfor ];
  }; 
}
