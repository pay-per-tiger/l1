#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

typedef unsigned long long uptr;
static char opt[256];

static void
usage(char *argv0)
{
	printf("usage: %s -a <alignment> -s <symbol> [ -p <abi_prefix> ] [ -S <section> ] [ -l <maxlen> ] <infile> <outfile>\n",
	       argv0);
	exit(1);
}

int
main(int argc, char *argv[])
{
	int ofd;
	int c;
	uptr align;
	char *sym;
	char *ep;
	char *infile, *outfile;
	char *prefix;
	char *section;
	char *flags;
	FILE *of;

	align = 0;
	sym = 0;
	prefix = "";
	flags = "";
	section = "savedheap";

	while(-1 != (c = getopt(argc, argv, "a:f:hl:p:s:S:")))
		switch(c) {
		case 'a':
			opt['a'] = 1;
			align = strtoull(optarg, &ep, 0);
			if(*ep != '\0')
				usage(argv[0]);
			break;
		case 'f':
			flags = optarg;
			break;
		case 's':
			opt['s'] = 1;
			sym = optarg;
			break;
		case 'S':
			section = optarg;
			break;
		case 'p':
			prefix = optarg;
			break;
		case 'h':
		case '?':
			usage(argv[0]);
			break;
		}

	if(opt['a'] == 0 || opt['s'] == 0)
		usage(argv[0]);

	if(argc-optind != 2)
		usage(argv[0]);

	infile = argv[optind];
	outfile = argv[optind+1];

	ofd = open(outfile, O_TRUNC|O_CREAT|O_WRONLY, 0664);
	if(0 > ofd) {
		fprintf(stderr, "open: %s: %s\n", outfile, strerror(errno));
		exit(1);
	}

	of = fdopen(ofd, "w");
	if(!of) {
		fprintf(stderr, "fdopen: %s: %s\n", outfile, strerror(errno));
		exit(1);
	}

	fprintf(of, ".section %s, \"%s\"\n", section, flags);
	if(align)
		fprintf(of, ".balign 0x%x\n", (int)align);
	fprintf(of, ".globl\t%s%s\n", prefix, sym);
	fprintf(of, ".globl\t%send%s\n", prefix, sym);
	fprintf(of, "%s%s:\n", prefix, sym);
	fprintf(of, ".incbin \"%s\"\n", infile);
	fprintf(of, "%send%s:\n", prefix, sym);
	fflush(of);
	close(ofd);
	return 0;
}
