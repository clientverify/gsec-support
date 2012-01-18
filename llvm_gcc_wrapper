#!/usr/bin/python

import commands
import os
import sys
import time

from optparse import OptionParser

# Config
g_soft_float_debug = False
g_soft_float = False
g_logging = True

#llvmroot           = os.getenv("LLVM_ROOT")
#llvmgccroot        = os.getenv("LLVMGCC_ROOT")
#llvmgccdir         = llvmgccroot+"/bin/"
#llvm_lib_dir       = llvmroot+"/lib"
#llvm_bin_dir       = llvmroot+"/bin"
#llvmld  = llvm_bin_dir+"/llvm-ld "+llvmldflags
#llvmgcc = llvmgccdir+"/llvm-gcc "+llvmgccflags

bc_libs = ' '

llvmgccflags = " "

llvmldflags = " "
#llvmldflags += " -disable-opt "

llvmgccargs = " "

dirname, filename = os.path.split(os.path.abspath(sys.argv[0]))

llvmld  = dirname+"/../local/bin/llvm-ld"
llvmgcc = dirname+"/../local/bin/llvm-gcc"
llvmopt = dirname+"/../local/bin/opt"

def log(s):
    if g_logging:
        print >>logstream, s

def emptypass(args,dolinking):
    # Compile
    cmd = llvmgcc+" "+" ".join(args)+" --emit-llvm -c"
    log("Empty pass compile command: "+cmd)
    result = commands.getstatusoutput(cmd)
    if result[0] != 0:
        print "compile failed."
        log("Compile failed:")
        log(result[1])
        sys.exit(result[0])

    if dolinking:
        # Link
        ldargs = makeldargs(args)
        cmd = llvmld
        for arg in ldargs:
            if arg.endswith(".c"):
                arg = arg[:-1]+"o"
            cmd += " "+arg
        log("Empty pass link command: "+cmd)
        result = commands.getstatusoutput(cmd)
        if result[0] != 0:
            print "link failed."
            log("Link failed:")
            log(result[1])
            sys.exit(result[0])

def compilepass(args,cc_args,dolinking,outfile):
    if dolinking:
        # Check for as-yet-uncompiled arguments
        ldargs = []
        for arg in args:
            if arg.endswith(".c") and not arg.startswith("-"):
                tempcontents = open(arg).read()
                if tempcontents.find("strlcpy") != -1:
                    log("STRLCPY")
                # Compile it, then transform the name
                cmd = llvmgcc+" --emit-llvm "+llvmgccargs+" "+" ".join(optionsonly(args))+" -c "+arg+" -o "+arg[:-2]+".o"
                log("Single-compile command: "+cmd)
                result = commands.getstatusoutput(cmd)
                if result[0] != 0:
                    print "Single-compile failed."
                    log("Single-compile failed:")
                    log(result[1])
                    sys.exit(result[0])
                if result[1] != "":
                    log("Single-compile output:")
                    log(result[1])
                ldargs.append(arg[:-2]+".o")
            else:
                # It's an option or it's already compiled -- keep it
                ldargs.append(arg)

        ldargs = makeldargs(ldargs)
        cmd = " ".join([llvmld, " ".join(ldargs), bc_libs])

    else:
        if outfile.endswith(".o"):
            cmd = llvmgcc+" "+llvmgccargs+" -D__GNUC__ --emit-llvm "+' '.join(cc_args)+" -o "+outfile+".orig"
        else:
            cmd = llvmgcc+" "+llvmgccargs+" -D__GNUC__ --emit-llvm "+' '.join(cc_args)

    log("Compile command: "+cmd)
    result = commands.getstatusoutput(cmd)
    if result[0] != 0:
        print "compile failed."
        log("Compile failed:")
        log(result[1])
        sys.exit(result[0])
    if result[1] != "":
        log("Compile non-empty output:")
        log(result[1])
        #sys.exit(1)

    return outfile
    
def softfloatpass(outfile):
    # Form the command
    if not g_soft_float:
        log("Skipping softfloat pass")
        cmd = "cp "+outfile+".orig "+outfile
    else:
        log("Performing soft float pass")
        if outfile.endswith(".o") or outfile.endswith(".os"):
            cmd = llvmopt
            if g_soft_float_debug:
                cmd += " -debug"
            cmd += " -disable-opt -load "+llvm_lib_dir+"/LLVMFloatLax.so -dce -floatlax -print < "+outfile+".orig > "+outfile

    # Run the command
    log("Soft float command: "+cmd)
    result = commands.getstatusoutput(cmd)
    if result[0] != 0:
        print "cmd failed:",cmd
        log("cmd failed: "+cmd)
        log(result[1])
        sys.exit(result[0])
    
def makeldargs(args):
    ldargs = []
    for arg in args:
        if arg != "-g" \
                and arg != "-Os" \
                and arg != "-xc" \
                and arg != "-O2" \
                and not arg.startswith("-D") \
                and not arg.startswith("-I") \
                and not arg.startswith("-falign-jumps=") \
                and not arg.startswith("-falign-loops=") \
                and not arg.startswith("-fno-stack-protector"):
            ldargs.append(arg)
    return ldargs

def optionsonly(args):
    optargs = []
    for arg in args:
        if arg.startswith("-") and arg != "-o":
            optargs.append(arg)
    return optargs

def config():
    args = list(sys.argv[1:])
    log("Full args: "+" ".join(args))

    # Check to see if we need to link
    if "-c" in args:
        dolinking = False
        log("\tNot linking")
    else:
        dolinking = True
        log("\tDo linking")

    # Get output file name
    cc_args = list(args)
    if "-o" in args:
        idx = args.index("-o")
        if idx == len(args)-1:
            raise Exception("'-o' can't be last argument.")
        outfile = args[idx+1]
        del cc_args[idx+1]
        del cc_args[idx]
    else:
        outfile = None
    log("cc_args: "+str(cc_args))
    log("outfile: "+str(outfile))
    return (args,cc_args,dolinking,outfile)

def main():
    # Get config data from args
    args,cc_args,dolinking,outfile = config()

    if outfile is None:
        log("Doing empty pass...")
        #emptypass(args,dolinking)
        outfile = compilepass(args,cc_args,dolinking,'a.out')
    else:
        # Create outfile.orig
        log("Doing compile pass")
        outfile = compilepass(args,cc_args,dolinking,outfile)

        # Software float pass
        if not dolinking:
            softfloatpass(outfile)

if __name__ == '__main__':
    if g_logging:
      logstream = open("llvm-gcc.log","a")
    #sys.stdout = logstream
    #sys.stderr = logstream
    for i in range(len(sys.argv)):
        sys.argv[i] = sys.argv[i].replace('"','\\"')
    log("\n----------------")
    log("Got: "+" ".join(sys.argv))
    main()
