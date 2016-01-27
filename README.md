# BlueHydra
## Bluetooth device discovery service
### :blue_book: :blue_car: :blue_heart: :large_blue_circle: :large_blue_diamond: 

## Config Options

The config file is located in `/opt/pwnix/pwnix-config/blue_hydra.json` on
Pwnie devices. On systems which do no have the /opt/pwnix/pwnix-config
directory the service will default to looking in the root of the services
directory (where this README file is located. It will still be called
`blue_hydra.json`

Currently there are 3 supported config options

* `log_level`: set the log level. Defaults to `info`. If `debug` log level is
  set device files will be created in the `devices/` dir so that it can be
  easily assessed as to what will be sent to pulse and to hunt for missing
  attributes in post-parser data blogs.
* `file`: when a file is set discovery mode will be disabled and all the
  `btmon` output will be assumed to be read out of the specified file.  
* `bt_device`: specifies which Bluetooth adapter will be used for discovery.
  Defaults to `hci0`.

## TODO:

Some stuff to do
* handle alt UUIDs which contain paren
* rate limit incoming RSSIs to 1 per timeframe
* Investigate duplicate classic_features_bitmaps...
  ```
  W, [2016-01-27T15:51:44.838857 #18723]  WARN -- : 00:61:71:D0:E1:EF multiple values detected for classic_features_bitmap: ["0xbf 0xfe 0xcf 0xfe 0xdb 0xff 0x7b 0x87", "0x07 0x00 0x00 0x00 0x00 0x00 0x00 0x00", "0x000002a8"]. Using first value...
  ```
