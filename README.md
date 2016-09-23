# BlueHydra

BlueHydra is a Bluetooth device discovery service built on top of the `bluez` 
library. BlueHydra makes use of ubertooth where available and attempts to track
both classic and low energy (LE) bluetooth devices over time. 

## Installation

### Pwnie Sensor
On a Pwnie Express sensor this will be installed as a system service with 
the regular updates. 

### Non Pwnie device
On non Pwnie Express systems the files in this repository can be run directly. 

Ensure that the following packages are installed: 

```
bluez
bluez-test-scripts
python-bluez
python-dbus
ubertooth # where applicable
sqlite3
libsqlite3-dev
```

In addition to the Bluetooth packages listed above you will need to have Ruby
version 2.1 or higher installed, as well as Ruby development headers for gem compilation (on
Debian-based systems, this is the `ruby-dev` package).

On Debian-based systems, these packages can be installed with the following command line:

```sudo apt-get install ruby ruby-dev bluez bluez-test-scripts python-bluez python-dbus libsqlite3-dev ubertooth```

With ruby installed add the `bundler` gem and
then run `bundle install` inside the checkout directory. 

Once all dependencies are met simply run `./bin/blue_hydra` to start discovery.
If you experience gem inconsistency try running `bundle exec ./bin/blue_hydra` instead.

There are a few flags that can be passed to this script: 

* `-d` or `--daemonize`: suppress CLI output and run in background
* `-z` or `--demo`: run with CLI output but mask displayed macs for demo purposes
* `-p` or `--pulse`: attempt to send data to Pwn Pulse


## Recommended Hardware
BlueHydra should function with most internal bluetooth cards but we recommend 
using the Sena UD100 adapter.

Additionally you can make use of Ubertooth One hardware to detect active devices
not in discoverable mode.

**Note:** using an Ubertooth One is _not_ a replacement for a conventional
bluetooth dongle. 

## Configuring Options

The config file is located in `/opt/pwnix/pwnix-config/blue_hydra.yml` on
Pwnie devices. On systems which do no have the /opt/pwnix/pwnix-config
directory the service will default to looking in the root of the services
directory (where this README file is located. It will still be called
`blue_hydra.yml`

The following options can be set:

* `log_level`: defaults to info level, can be set to debug for much more verbosity. If set to `false` no log or rssi log will be created.
* `bt_device`: specify device to use as main bluetooth interface, defaults to `hci0`
* `info_scan_rate`: rate at which to run info scan in seconds, defaults to 60
* `status_sync_rate`: rate at which to sync device status to Pulse in seconds
* `btmon_log`: `true|false`, if set to true will log filtered btmon output
* `btmon_rawlog`: `true|false`, if set to true will log unfiltered btmon output
* `file`: if set to a filepath that file will be read in rather than doing live device interactions
* `rssi_log`: `true|false`, if set will log serialized RSSI values
* `aggressive_rssi`: `true|false`, if set will agressively send RSSIs to Pulse

Helping with Development

PR's should be targeted against the "develop" branch.
Develop branch gets merged to master branch and tagged during the release process.

## Troubleshooting

### `Parser thread "\xC3" on US-ASCII` 

If you encounter an error like `Parser Thread "\xC3" on US-ASCII` it may be due
to an encoding misconfiguration on your system. 

On Debian like systems, this can be resolved by setting locale encodings as follows:

```
sudo locale-gen en_US.UTF-8 
sudo locale-gen en en_US en_US.UTF-8
sudo dpkg-reconfigure locales
export LC_ALL = "en_US"
```

This issue and solution brought up by [llazzaro](https://github.com/llazzaro)
[here](https://github.com/pwnieexpress/blue_hydra/issues/65).
