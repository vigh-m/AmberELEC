#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present AmberELEC (https://github.com/AmberELEC)

. /etc/profile

DEVICE=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

if [ "$DEVICE" == "Anbernic RG351P" ]; then
  ffmpeg -loglevel quiet -i /usr/config/splash/splash-480.png -f rawvideo -pix_fmt bgra - > /dev/fb0
elif [ "$DEVICE" == "Anbernic RG552" ]; then
  ply-image /usr/config/splash/splash-1920.png
else
  ffmpeg -loglevel quiet -i /usr/config/splash/splash-640.png -f rawvideo -pix_fmt bgra - > /dev/fb0
fi
