# Local support report

Run as an ordinary user on Yurei:

```sh
yurei-support
yurei-support --output yurei-report.json
```

The command reads system information and prints JSON or creates a new report
file. It does not change settings, need root, install anything, access the
network, upload a report, or overwrite an existing report file.

It includes OS/kernel versions, graphics PCI IDs and driver names, display
connector status, memory and root-disk capacity, selected core package
versions, the status of four named login/network services, and a count of
failed system services. Missing tools and unavailable information are normal
on an early build and are reported without stopping collection.

It does not intentionally collect hostnames, usernames, home paths, IP/MAC
addresses, serial numbers, monitor EDID, Wi-Fi names, process lists, full logs,
or a complete installed-app list. Review a report before choosing to share it.
Custom OS version strings and package versions are retained as version data.

The native package recipe is `independent/packages/yurei-support`. During
development it can also run directly with:
`python3 independent/packages/yurei-support/yurei-support.py`.
