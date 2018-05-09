# tpad
A teleporter-pads mod for Minetest

Developed and tested on Minetest 0.4.16 - try in other versions at your own risk :)

WIP mod forum discussion: https://forum.minetest.net/viewtopic.php?f=9&t=20081

# recipe
    W = any wood planks
    B = bronze ingot
  
    WBW
    BWB
    WBW

# features
- place down a pad and the teleport station will be immediately active
- right-click on a pad to open the interface
- doubleclick on a station in the station list to teleport to it (or select it and click "teleport")
- edit the name of each station (then either hit "enter" or click "save")
- you can delete any station from anywhere (apart from the one you clicked to open the interface, you have to destroy it manually)
- deleting a remote station you'll lose the relative pad
- issue "/tpad" on the chat to get a waypoint to the closest station
- either teleport or issue "/tpad off" to turn the waypoint HUD off
- each player has its own list of stations
- any player can use any station, but only its owner can dig a station or delete a remote station from the interface
