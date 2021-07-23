import sys
import os
from argparse import ArgumentParser

try:
    sys.path.insert(0, os.getcwd())
    from kbox_maintainer import check
    from kbox_maintainer import recover
    from kbox_maintainer import log
    from kbox_maintainer import resource
except KeyboardInterrupt:
    raise SystemExit()

if __name__ == "__main__":

    parser = ArgumentParser(
        description="===Kbox Maintainment tool set usage===",
        epilog="Hope this tool is helpful :)",
        allow_abbrev=False,
    )

    subparsers = parser.add_subparsers(
        title='maintainer options',
        description='option is required to run different task',
        metavar='option',
        dest='option',
        help='help details',
        required=True
    )

    check_parser = subparsers.add_parser(
        'check',
        help='check container(s) status'
    )

    check_parser.add_argument(
        "containers",
        nargs='*',
        metavar="containers",
        help='container name or id, check all when no container is specified'
    )
    check_parser.set_defaults(func=check)

    recover_parser = subparsers.add_parser(
        'recover',
        help='recover container(s)'
    )

    recover_parser.add_argument(
        "containers",
        nargs='*',
        metavar="containers",
        help='container name or id, recover all when no container is specified'
    )
    recover_parser.set_defaults(func=recover)

    log_parser = subparsers.add_parser(
        'log',
        help='log container(s)'
    )

    log_parser.add_argument(
        "containers",
        nargs='*',
        metavar="containers",
        help='container name or id, log all when no container is specified'
    )
    log_parser.set_defaults(func=log)

    resource_parser = subparsers.add_parser(
        'resource',
        help='resource container(s)'
    )

    resource_parser.add_argument(
        "containers",
        nargs='*',
        metavar="containers",
        help='container name or id, resource all when none is specified'
    )
    resource_parser.set_defaults(func=resource)

    args = parser.parse_args(sys.argv[1:])
    args.func(args.containers)
