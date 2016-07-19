#!/bin/bash
if [ ! -c /dev/rfkill ]; then
  printf "rfkill not supported\n"
  exit 2
fi
if [ ! -x "$(command -v rfkill 2>&1)" ]; then
  printf "Your kernel supports rfkill but you don't have rfkill installed.\n"
  printf "To ensure devices are unblocked you must install rfkill.\n"
  exit 3
fi

index="$(rfkill list | grep ${1} | awk -F: '{print $1}')"
if [ -z "$index" ]; then
  exit 187
fi

rfkill_check() {
  rfkill_status="$(rfkill list ${index} 2>&1)"
  if [ $? != 0 ]; then
    printf "rfkill error: ${rfkill_status}\n"
    return 187
  elif [ -z "${rfkill_status}" ]; then
    printf "rfkill had no output, something went wrong.\n"
    exit 1
  else
    soft=$(printf "${rfkill_status}" | grep -i soft | awk '{print $3}')
    hard=$(printf "${rfkill_status}" | grep -i hard | awk '{print $3}')
    if [ "${soft}" = "yes" ] && [ "${hard}" = "no" ]; then
      return 1
    elif [ "${soft}" = "no" ] && [ "${hard}" = "yes" ]; then
      return 2
    elif [ "${soft}" = "yes" ] && [ "${hard}" = "yes" ]; then
      return 3
    fi
  fi
  return 0
}

rfkill_reset() {
  #attempt block and CHECK SUCCESS
  rfkill_status="$(rfkill unblock ${1} 2>&1)"
  if [ $? != 0 ]; then
    printf "rfkill error: ${rfkill_status}\n"
    printf "Unable to block.\n"
    return 1
  else
    sleep 1
    rfkill_unblock
    return $?
  fi
}

rfkill_unblock() {
  #attempt unblock and CHECK SUCCESS
  rfkill_status="$(rfkill unblock ${1} 2>&1)"
  if [ $? != 0 ]; then
    printf "rfkill error: ${rfkill_status}\n"
    printf "Unable to unblock.\n"
    return 1
  else
    sleep 1
    return 0
  fi
}

#check if rfkill is set and cry if it is
rfkill_check $index
rfkill_retcode="$?"
case ${rfkill_retcode} in
  0) rfkill_reset $index ;;
  1) rfkill_unblock $index ;;
  *) printf "Unable to automagically fix\n" ;;
esac
