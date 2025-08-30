# lsdtool

lsdtool is a linux utility intended to make it easier to patch java classes / functions that are included in the lsd.jxe compiled library in MIB2 infotainment units

Based on https://gitlab.com/alelec/mib2-lsd-patching/, this tool provides some advantages over the original, notably bundling python2 binaries along with JXE2JAR utility and patching the 32bit j9 JDK to run on modern platforms


# Dependencies

* git - only to clone the repository, not really used by the tool itself
* curl - to download the j9 JDK
* unzip - to unpack the downloaded j9 JDK

And:
* x86 32bit libc - required to run 32bit j9 JDK
  * lib32-gcc-libs for archlinux
  * libc6:i386 for debian/ubuntu
* patchelf - required to patch the j9 JDK
* file & ldd - pre-run checks

Or:
* docker


# Installation

```
git clone https://github.com/JeniCzech92/lsdtool/
```
to install it in ~/.local/share/ and make symlink to ~/.local/bin/, so it can be called from anywhere:

```
bash ./lsdtool/lsdtool.sh -i
```

If you want to get rid of it later:
```
rm $HOME/.local/bin/lsdtool
rm -r $HOME/.local/share/lsdtool
```


# Usage

lsdtool -h shows list of available commands.

```
Usage: lsdtool.sh [OPTIONS] [SOURCE] [DESTINATION] [CLASSPATH]

Options:
  -h, --help             Show this help message
  -x, --jxe              Convert lsd.jxe to lsd.jar and decompile it
       [SOURCE]          Source java file. Default lsd.jxe
       [DESTINATION]     Destination folder, default ./lsd_java
  -a, --jar              Decompile lsd.jar to destination
       [SOURCE]          Source java file. Default lsd.jar
       [DESTINATION]     Destination folder, default ./lsd_java

  -c, --copy             Copies files that match string to a different folder
       [SOURCE]          Source directory, such as ./lsd_java
       [DESTINATION]     Destination directory, such as ./patch
       [STRING]          String to match
  -t  --trim             Trims unmodified classes from patch directory
       [PATCH]           Patch directory, default ./patch
       [SOURCE]          Original decompiled java classes, default ./lsd_java

  -b, --build            Build JAR patch file
       [SOURCE]          Source patch data, default ./patch
       [DESTINATION]     Target patch file, default [SOURCE].jar
       [CLASSPATH]       Original jar file, default lsd.jar
  -n, --nocleanup        Skip cleanup during build (may cause build failure)

  -i, --install          lsdtool can be portable, but it can also be installed
  -d, --docker           run the toolchain inside docker - default on mac,
                         not available on windows, optional on linux
```
