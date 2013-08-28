#!/bin/sh

getDevice() {
  echo "Enter the cf card" 
  read DEVICE
  if [ -z $DEVICE ]; then
    echo "No disk given"
    exit 1
  fi
}

getDevice


CWD=`pwd`
WORKDIR=sandbox
SRCDIR=${BSDSRCDIR:-/usr/src}
DESTDIR=${DESTDIR:-${CWD}/${WORKDIR}}
KERNELFILE=${KERNELFILE:-${CWD}/obj/bsd.gz}
SUDO=sudo
MOUNTPOINT=/mnt
TMPFILE=`mktemp`
TEMPFILE=/tmp/build-diskimage.tmp.$$

# This is for boot.conf and should match the kernel ttyspeed.
# Which should be 9600 for GENERIC-RD, 38400 for WRAP12 and 19200 for the rest.
TTYSPEED=${TTYSPEED:-19200}

${SUDO} disklabel ${DEVICE} > ${TMPFILE}

# drive geometry information -- get the right one for your flash!!

totalsize=`grep "total sectors:" ${TMPFILE} | awk '{ print $3 }'`
bytessec=`grep "bytes/sector:" ${TMPFILE} | awk '{ print $2 }'`
sectorstrack=`grep "sectors/track:" ${TMPFILE} | awk '{ print $2 }'`
sectorscylinder=`grep "sectors/cylinder:" ${TMPFILE} | awk '{ print $2 }'`
trackscylinder=`grep "tracks/cylinder:" ${TMPFILE} | awk '{ print $2 }'`
cylinders=`grep "cylinders:" ${TMPFILE} | awk '{ print $2 }'`

if [ ! -f $KERNELFILE ]; then
  echo "Kernelfile $KERNELFILE not found...."
  exit 1
fi

echo ""
echo "Running fdisk on ${DEVICE}... (Ignore any sysctl(machdep.bios.diskinfo): Device not configured warnings)"
${SUDO} fdisk -c $cylinders -h $trackscylinder -s $sectorstrack -f ${DESTDIR}/usr/mdec/mbr -e $DEVICE << __EOC >/dev/null
reinit
update
write
quit
__EOC

let asize=$totalsize-$sectorstrack

echo "type: SCSI" >> $TEMPFILE
echo "disk: vnd device" >> $TEMPFILE
echo "label: fictitious" >> $TEMPFILE
echo "flags:" >> $TEMPFILE
echo "bytes/sector: ${bytessec}" >> $TEMPFILE
echo "sectors/track: ${sectorstrack}" >> $TEMPFILE
echo "tracks/cylinder: ${trackscylinder}" >> $TEMPFILE
echo "sectors/cylinder: ${sectorscylinder}" >> $TEMPFILE
echo "cylinders: ${cylinders}" >> $TEMPFILE
echo "total sectors: ${totalsize}" >> $TEMPFILE
echo "interleave: 1" >> $TEMPFILE
echo "trackskew: 0" >> $TEMPFILE
echo "cylinderskew: 0" >> $TEMPFILE
echo "headswitch: 0           " >> $TEMPFILE
echo "track-to-track seek: 0  " >> $TEMPFILE
echo "drivedata: 0 " >> $TEMPFILE
echo "" >> $TEMPFILE
echo "16 partitions:" >> $TEMPFILE
echo "a:	$asize	$sectorstrack	4.2BSD	2048	16384	16" >> $TEMPFILE
echo "c:	$totalsize	0	unused	0	0" >> $TEMPFILE

echo ""
echo "Installing disklabel..."
${SUDO} disklabel -R $DEVICE $TEMPFILE
rm $TEMPFILE

echo ""
echo "Creating new filesystem..."
${SUDO} newfs -q /dev/r${DEVICE}a

echo ""
echo "Mounting destination to ${MOUNTPOINT}..."
if ! ${SUDO} mount -o async /dev/${DEVICE}a ${MOUNTPOINT}; then
  echo Mount failed..
  exit
fi

echo ""
echo "Copying bsd kernel, boot blocks and /etc/boot.conf..."
${SUDO} cp ${DESTDIR}/usr/mdec/boot ${MOUNTPOINT}/boot
${SUDO} cp ${KERNELFILE} ${MOUNTPOINT}/bsd
${SUDO} mkdir ${MOUNTPOINT}/etc
${SUDO} sed "/^stty/s/19200/${TTYSPEED}/" < ${CWD}/initial-conf/boot.conf > ${MOUNTPOINT}/etc/boot.conf

echo ""
echo "Installing boot blocks..."
${SUDO} /usr/mdec/installboot ${MOUNTPOINT}/boot ${DESTDIR}/usr/mdec/biosboot ${DEVICE}

${SUDO} mkdir ${MOUNTPOINT}/conf
${SUDO} mkdir ${MOUNTPOINT}/pkg
# Here is where you add your own packages and configuration to the flash...

echo ""
echo "Unmounting and cleaning up..."
${SUDO} umount $MOUNTPOINT
${SUDO} rm -f ${TMPFILE}

echo ""
echo "And we are done..."
echo "Run \"mountimage.sh $IMAGEFILE\" to add configuration and packages."
echo "When you are done with the configuration, gzip the imagefile and move"
echo "it to the system with a flashwriter."
echo "Use \"gunzip -c image.gz | dd of=/dev/sd0c\" on unix to write to flash"
echo "On Windows you can use http://m0n0.ch/wall/physdiskwrite.php"
echo "Both these utilities allow the gzipped image to be used directly."
