# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2020-present Fewtarius
# Copyright (C) 2021-present AmberELEC (https://github.com/AmberELEC)

PKG_NAME="amberelec"
PKG_VERSION="1.0"
PKG_LICENSE="GPLv3"
PKG_DEPENDS_TARGET="toolchain ${OPENGLES} emulationstation retroarch retrorun klbi lib32"
PKG_LONGDESC="AmberELEC Meta Package"
PKG_TOOLCHAIN="make"

if [[ "${BASE_BUILD}" == "true" ]];
then
  PKG_EMUS=""
else
  LIBRETRO_CORES="beetle-gba beetle-lynx beetle-ngp beetle-pce beetle-pce-fast beetle-supergrafx beetle-vb beetle-wswan \
                  doublecherrygb fake08 fbalpha2012 fbneo fceumm flycast gambatte \
                  gearsystem genesis-plus-gx genesis-plus-gx-wide gpsp gw-libretro handy mgba \
                  mupen64plus-nx mame2003-plus nestopia \
                  pcsx_rearmed picodrive pokemini ppsspp prboom quicknes \
                  sameboy scummvm smsplus-gx snes9x snes9x2005_plus snes9x2010 stella swanstation \
                  tgbdual vecx"

  PKG_EMUS="${LIBRETRO_CORES}"

  PKG_EMUS+=" drastic"
fi

PKG_TOOLS="bash dialog grep wget ffmpeg libjpeg-turbo common-shaders glsl-shaders util-linux xmlstarlet sixaxis jslisten evtest mpv bluetool rs97-commander-sdl2 jslisten gzip odroidgoa-utils rs97-commander-sdl2 textviewer 351files jstest-sdl sdljoytest evdev-joystick gptokeyb fbgrab"
PKG_RETROPIE_DEP="pyudev six git dbus-python coreutils"
PKG_DEPENDS_TARGET+=" ${PKG_TOOLS} ${PKG_RETROPIE_DEP} ${PKG_EMUS} ports webui"

make_target() {
  :
}

makeinstall_target() {
  ## Remove libretro cores from unsupported devices
  if [[ ! ${DEVICE} == "RG552" ]]; then
    mkdir -p ${INSTALL}/usr/config/emulationstation
    cp -f $(get_build_dir emulationstation)/.install_pkg/usr/config/emulationstation/es_systems.cfg ${INSTALL}/usr/config/emulationstation/es_systems.cfg
    for CORE in ${LIBRETRO_CORES_EXTRA}; do
      if [[ $CORE == "geolith" ]]; then
        sed -i "s|<extension>.neo .7z .zip</extension>|<extension>.7z .zip</extension>|g" ${INSTALL}/usr/config/emulationstation/es_systems.cfg
      fi
      if [[ $CORE == "melonds" ]]; then
        sed -i -e '/<emulator name/{:a;N;/<\/emulator>/!ba;/melonds/d}' ${INSTALL}/usr/config/emulationstation/es_systems.cfg
      fi
      sed -i "s|<core>$CORE</core>||g" ${INSTALL}/usr/config/emulationstation/es_systems.cfg
      sed -i '/^[[:space:]]*$/d' ${INSTALL}/usr/config/emulationstation/es_systems.cfg
    done
  fi

  mkdir -p ${INSTALL}/usr/config/SDL-GameControllerDB
  cp ${PKG_DIR}/SDL_GameControllerDB/gamecontrollerdb.txt ${INSTALL}/usr/config/SDL-GameControllerDB

  mkdir -p ${INSTALL}/usr/config/
  rsync -av ${PKG_DIR}/config/* ${INSTALL}/usr/config/

  if [ ! "${DEVICE}" == "RG351MP" ] && [ ! "${DEVICE}" == "RG351V" ]; then
    rm -rf ${INSTALL}/usr/config/distribution/modules/display_fix.sh
  fi

  if [ ! "${DEVICE}" == "RG351MP" ]; then
    rm -rf ${INSTALL}/usr/config/distribution/modules/joyleds_conf.sh
  fi

  ln -sf /storage/.config/distribution ${INSTALL}/distribution
  find ${INSTALL}/usr/config/distribution/ -type f -exec chmod o+x {} \;

  if [ "${DEVICE}" == "RG351P" ]; then
    cp ${INSTALL}/usr/config/distribution/configs/distribution.conf.351p ${INSTALL}/usr/config/distribution/configs/distribution.conf
  elif  [ "${DEVICE}" == "RG351V" ] || [ "${DEVICE}" == "RG351MP" ]; then
    cp ${INSTALL}/usr/config/distribution/configs/distribution.conf.351v ${INSTALL}/usr/config/distribution/configs/distribution.conf
  elif [ "${DEVICE}" == "RG552" ]; then
    cp ${INSTALL}/usr/config/distribution/configs/distribution.conf.552  ${INSTALL}/usr/config/distribution/configs/distribution.conf
  fi

  sed -i "s/system.hostname=AmberELEC/system.hostname=${DEVICE}/g" ${INSTALL}/usr/config/distribution/configs/distribution.conf

  echo "${LIBREELEC_VERSION}" > ${INSTALL}/usr/config/.OS_VERSION

  echo "${DEVICE}" > ${INSTALL}/usr/config/.OS_ARCH

  echo "$(date)" > ${INSTALL}/usr/config/.OS_BUILD_DATE

  mkdir -p ${INSTALL}/usr/bin/

  ## Compatibility links for ports
  ln -s /storage/roms ${INSTALL}/roms
  ln -s /roms/ports/PortMaster ${INSTALL}/portmaster
  #ln -sf /storage/roms/opt ${INSTALL}/opt

  mkdir -p ${INSTALL}/usr/lib
  ln -s /usr/lib32/ld-linux-armhf.so.3 ${INSTALL}/usr/lib/ld-linux-armhf.so.3

  mkdir -p ${INSTALL}/usr/share/retroarch-overlays
  if [ "${DEVICE}" == "RG351P" ]; then
    cp -r ${PKG_DIR}/overlay-p/* ${INSTALL}/usr/share/retroarch-overlays
  elif [ "${DEVICE}" == "RG351V" ] || [ "${DEVICE}" == "RG351MP" ]; then
    cp -r ${PKG_DIR}/overlay-v/* ${INSTALL}/usr/share/retroarch-overlays
  elif [ "${DEVICE}" == "RG552" ]; then
    cp -r ${PKG_DIR}/overlay-552/* ${INSTALL}/usr/share/retroarch-overlays
  fi

  mkdir -p ${INSTALL}/usr/share/libretro-database
     touch ${INSTALL}/usr/share/libretro-database/dummy

  mkdir -p ${INSTALL}/usr/config/splash

  find_file_path "splash/splash-*.png" && cp ${FOUND_PATH} ${INSTALL}/usr/config/splash
  find_file_path "splash/blank.png" && cp ${FOUND_PATH} ${INSTALL}/usr/config/splash
}

post_install() {
# Remove unnecesary Retroarch Assets and overlays
  for i in FlatUX Automatic Systematic branding nuklear nxrgui pkg switch wallpapers zarch COPYING; do
    rm -rf "${INSTALL}/usr/share/retroarch-assets/${i}"
  done

  for i in automatic dot-art flatui neoactive pixel retroactive retrosystem systematic convert.sh NPMApng2PMApng.py; do
    rm -rf "${INSTALL}/usr/share/retroarch-assets/xmb/${i}"
  done

  mkdir -p ${INSTALL}/etc/retroarch-joypad-autoconfig
  if [[ "${DEVICE}" == "RG351P" ]] || [[ "${DEVICE}" == "RG351V" ]]; then
    cp -r ${PKG_DIR}/gamepads/OpenSimHardware* ${INSTALL}/etc/retroarch-joypad-autoconfig
  else
    cp -r ${PKG_DIR}/gamepads/GO-Super* ${INSTALL}/etc/retroarch-joypad-autoconfig
  fi
  ln -sf amberelec.target ${INSTALL}/usr/lib/systemd/system/default.target
  enable_service amberelec-autostart.service
  enable_service lastgame.service
  if [[ "${DEVICE}" == "RG552" ]]; then
    enable_service fan_control.service
  fi

  if [[ "${DEVICE}" =~ "RG351" ]]; then
    cp -f  ${PKG_DIR}/clocks/RK3326/clocklimits ${INSTALL}/etc
  elif [[ "${DEVICE}" == "RG552" ]]; then
    cp -f  ${PKG_DIR}/clocks/RK3399/clocklimits ${INSTALL}/etc
  fi

  echo "" >${INSTALL}/etc/issue
  echo -e "\033[38;5;220m     _         _            \033[38;5;255m ___ _    ___ ___ " >>${INSTALL}/etc/issue
  echo -e "\033[38;5;220m    /_\  _ __ | |__  ___ _ _\033[38;5;255m| __| |  | __/ __|" >>${INSTALL}/etc/issue
  echo -e "\033[38;5;220m   / _ \| '  \| '_ \/ -_) '_\033[38;5;255m| _|| |__| _| (__ " >>${INSTALL}/etc/issue
  echo -e "\033[38;5;220m  /_/ \_\_|_|_|_.__/\___|_| \033[38;5;255m|___|____|___\___|" >>${INSTALL}/etc/issue
  echo -e "\033[0m" >>${INSTALL}/etc/issue
  echo "" >>${INSTALL}/etc/issue

  ln -s /etc/issue ${INSTALL}/etc/motd

  cp ${PKG_DIR}/sources/amberelec.dialogrc ${INSTALL}/etc
  cp ${PKG_DIR}/sources/autostart.sh ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/pico-8.sh ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/pico-8.sh "${INSTALL}/usr/config/distribution/modules/Start Pico-8.sh"
  cp ${PKG_DIR}/sources/scripts/* ${INSTALL}/usr/bin

  rm -f ${INSTALL}/usr/bin/{sh,bash,busybox,sort}
  cp $(get_build_dir busybox)/.install_pkg/usr/bin/busybox ${INSTALL}/usr/bin
  cp $(get_build_dir bash)/.install_pkg/usr/bin/bash ${INSTALL}/usr/bin
  cp $(get_build_dir coreutils)/.install_pkg/usr/bin/sort ${INSTALL}/usr/bin

  ln -sf bash ${INSTALL}/usr/bin/sh
  mkdir -p ${INSTALL}/etc
  echo "/usr/bin/bash" >>${INSTALL}/etc/shells
  echo "/usr/bin/sh" >>${INSTALL}/etc/shells

  echo "chmod 4755 ${INSTALL}/usr/bin/bash" >> ${FAKEROOT_SCRIPT}
  echo "chmod 4755 ${INSTALL}/usr/bin/busybox" >> ${FAKEROOT_SCRIPT}
  find ${INSTALL}/usr/ -type f -iname "*.sh" -exec chmod +x {} \;
  find ${INSTALL}/usr/bin -type f -exec chmod +x {} \;
}
