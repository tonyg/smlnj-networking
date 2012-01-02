# Network server programming with SML/NJ and CML

<i>1 January, 2010</i>

(Originally appeared as a [blog
post](http://www.lshift.net/blog/2010/01/01/network-server-programming-with-smlnj-and-cml). Mirror
of that post available
[here](http://homepages.kcbbs.gen.nz/tonyg/lshift_archive/network-server-programming-with-smlnj-and-cml-20100101.html).)

My experience with [SML/NJ](http://www.smlnj.org/) has been almost
uniformly positive, over the years. We [at LShift] used it extensively
in a previous project to write a compiler (targeting the .NET CLR) for
a pi-calculus-based language, and it was fantastic. One drawback with
it, though, is the lack of documentation. Finding out how to (a)
compile for and (b) use [CML](http://cml.cs.uchicago.edu/) takes real
stamina. I've only just now, after several hours poring over webpages,
mailing lists, and library source code, gotten to the point where I
have a running socket server.

## Download source code, building, and running

The following example is comprised of a `.cm` file for building the
program, and the `.sml` file itself. The complete sources:

 - [`test.cm`](https://raw.github.com/tonyg/smlnj-networking/master/test.cm)
 - [`test.sml`](https://raw.github.com/tonyg/smlnj-networking/master/test.sml)

Running the following command compiles the project:

    ml-build test.cm Testprog.main

The `ml-build` output is a heap file, with a file extension dependent
on your architecture and operating system. For me, right now, it
produces `test.x86-darwin`. To run the program:

    sml @SMLload=test

On Ubuntu, you will need to have run `apt-get install smlnj
libcml-smlnj libcmlutil-smlnj` to ensure both SML/NJ and CML are
present on your system.

## The build control file

The
[`test.cm`](https://raw.github.com/tonyg/smlnj-networking/master/test.cm)
file contains

    Group is
        $cml/basis.cm
        $cml/cml.cm
        $cml-lib/smlnj-lib.cm
        test.sml

which instructs the build system to use the CML variants of the basis
and the standard SML/NJ library, as well as the core CML library
itself and the source code of our program. For more information about
the SML CM build control system, see
[here](http://www.smlnj.org/doc/CM/index.html).

## The example source code

Turning to
[`test.sml`](https://raw.github.com/tonyg/smlnj-networking/master/test.sml)
now, we first declare the ML structure (module) we'll be
constructing. The structure name is also part of one of the
command-line arguments to `ml-build` above, telling it which function
to use as the main function for the program.

    structure Testprog = struct

Next, we bring the contents of the `TextIO` module into scope. This is
necessary in order to use the `print` function with CML; if we use the
standard version of `print`, the output is unreliable. The special CML
variant is needed. We also declare a local alias `SU` for the global
`SockUtil` structure.

    open TextIO
    structure SU = SockUtil

ML programs end up being written upside down, in a sense, because
function definitions need to precede their use (unless
mutually-recursive definitions are used). For this reason, the next
chunk is `connMain`, the function called in a new lightweight thread
when an inbound TCP connection has been accepted. Here, it simply
prints out a countdown from 10 over the course of the next five
seconds or so, before closing the socket. Multiple connections end up
running connMain in independent threads of control, leading
automatically to the natural and obvious interleaving of outputs on
concurrent connections.

    fun connMain s =
        let fun count 0 = SU.sendStr (s, "Bye!\r\n")
              | count n = (SU.sendStr (s, "Hello " ^ (Int.toString n) ^ "\r\n");
                           CML.sync (CML.timeOutEvt (Time.fromReal 0.5));
                           count (n - 1))
        in
            count 10;
            print "Closing the connection.\n";
            Socket.close s
        end

The function that depends on `connMain` is the accept loop, which
repeatedly accepts a connection and spawns a connection thread for it.

    fun acceptLoop server_sock =
        let val (s, _) = Socket.accept server_sock
        in
            print "Accepted a connection.\n";
            CML.spawn (fn () =&gt; connMain(s));
            acceptLoop server_sock
        end

The next function is the primordial CML thread, responsible for
creating the TCP server socket and entering the accept loop. We set
`SO_REUSEADDR` on the socket, listen on port 8989 with a connection
backlog of 5, and enter the accept loop.

    fun cml_main (program_name, arglist) =
        let val s = INetSock.TCP.socket()
        in
            Socket.Ctl.setREUSEADDR (s, true);
            Socket.bind(s, INetSock.any 8989);
            Socket.listen(s, 5);
            print "Entering accept loop...\n";
            acceptLoop s
        end

Finally, the function we told `ml-build` to use as the main entry
point of the program. The only thing we do here is disable SIGPIPE
(otherwise we get rudely killed if a remote client's socket closes!)
and start CML's scheduler running with a primordial thread
function. When the scheduler decides that everything is over and the
program is complete, it returns control to us. (The lone `end` closes
the `struct` definition way back at the top of the file.)

    fun main (program_name, arglist) =
        (UnixSignals.setHandler (UnixSignals.sigPIPE, UnixSignals.IGNORE);
         RunCML.doit (fn () =&gt; cml_main(program_name, arglist), NONE);
         OS.Process.success)

    end
