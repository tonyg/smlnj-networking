all: test

clean:
	find . -name .cm | xargs rm -rf
	rm -f test.x86-darwin

test:
	ml-build test.cm Testprog.main

run: all
	./run
