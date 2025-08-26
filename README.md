# lsdtool
lsdtool is a linux utility intended to make it easier to patch java classes / functions that are included in the lsd.jxe compiled library in MIB2 infotainment units
based on https://gitlab.com/alelec/mib2-lsd-patching/, this tool provides some advantages over the original, notably bundling python2 binaries along with JXE2JAR utility and patching the 32bit j9 JDK to run on modern platforms
# Usage
lsdtool -h shows list of available commands.

Usage: lsdtool.sh [OPTIONS] [SOURCE] [DESTINATION] [CLASSPATH]

Options:
  -h, --help             Show this help message
  -x, --jxe              Convert lsd.jxe to lsd.jar and decompile it
       [SOURCE]          Source java file. Default lsd.jxe
       [DESTINATION]     Destination folder, default ./lsd_java
  -a, --jar              Decompile lsd.jar to destination
       [SOURCE]          Source java file. Default lsd.jar
       [DESTINATION]     Destination folder, default ./lsd_java

  -b, --build            Build JAR patch file
       [SOURCE]          Source patch data, default ./patch
       [DESTINATION]     Target patch file, default [SOURCE].jar
       [CLASSPATH]       Original jar file, default lsd.jar
  -n, --nocleanup        Skip cleanup during build (may cause build failure)
  -i, --install          lsdtool can be portable, but it can also be installed
