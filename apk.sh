#!/bin/bash
#
# apk.sh v0.9.5
# author: ax
# site: github.com/ax
#
# References:
# https://koz.io/using-frida-on-android-without-root/
# https://github.com/sensepost/objection/
# https://github.com/NickstaDB/patch-apk
#

VERSION="v0.9.5"

APK_SH_HOME="${HOME}/.apk.sh"
mkdir -p $APK_SH_HOME

APKTOOL_DOWNLOAD_URL="https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.6.1.jar"
APKTOOL_PATH="$APK_SH_HOME/apktool_2.6.1.jar"

echo -e "[*] \033[1mapk.sh $VERSION \033[0m"
echo "[*] home dir is $APK_SH_HOME"

check_apk_tools(){
	if [ -f "$APKTOOL_PATH" ]; then
		echo "[*] apktool v2.6.1 exist in $APK_SH_HOME"
	else
		echo "[!] No apktool v2.6.1 found!"
		echo "[>] Downloading apktool from $APKTOOL_DOWNLOAD_URL"
		wget $APKTOOL_DOWNLOAD_URL -q --show-progress -P $APK_SH_HOME 
		APKTOOL_PATH="$APK_SH_HOME/apktool_2.6.1.jar"
	fi
	if  is_not_installed 'apksigner'; then
		echo "[>] No apksigner found!"
		echo "[>] Pls install apksigner!"
		exit
	fi
	if  is_not_installed 'zipalign'; then
		echo "[>] No zipalign found!"
		echo "[>] Pls install zipalign!"
		exit
	fi
	if  is_not_installed 'aapt'; then
		echo "[>] No aapt found!"
		echo "[>] Pls install aapt!"
		exit
	fi
	if  is_not_installed 'unxz'; then
		echo "[>] No unxz found!"
		echo "[>] Pls install unxz!"
		exit
	fi
	return 0
}

is_installed () {
	if [ ! -z `which $1` ]; then
		return 0
	fi
}

is_not_installed () {
	if [ -z `which $1` ]; then
		return 0
	fi
		return 1
}

apk_decode(){
	DECODE_CMD=$1
	echo -e "[>] \033[1mDecoding $APK_NAME\033[0m with $DECODE_CMD"
	if ! eval $DECODE_CMD; then 
		echo "[>] Sorry!"
		echo "[!] $DECODE_CMD return errors!"
		echo "[>] Bye!"
		exit
	fi
	echo "[>] Done!"
}

apk_build(){
	BUILD_CMD=$1
	echo -e "[>] \033[1mBuilding\033[0m with $BUILD_CMD"

	if ! eval $BUILD_CMD; then
		echo "[>] Sorry!"
		echo "[!] $BUILD_CMD return errors!"
		echo "[>] Bye!"
		exit
	fi
	echo "[>] Built!"
	echo "[>] Aligning with zipalign -p 4 ...."
	zipalign -p 4 file.apk file-aligned.apk
	echo "[>] Done!"

	KS="$APK_SH_HOME/my-new.keystore"
	if [ ! -f "$KS" ]; then
		echo "[!] Keystore does not exist!"
		echo "[>] Generating keystore..."
		keytool -genkey -v -keystore $KS -alias alias_name -keyalg RSA -keysize 2048 -validity 10000 -storepass password -keypass password -noprompt -dname "CN=noway, OU=ID, O=Org, L=Blabla, S=Blabla, C=US"
	else
		echo "[>] A Keystore exist!"
	fi
	echo "[>] Signing file.apk with apksigner..."
	apksigner sign --ks $KS --ks-pass pass:password file-aligned.apk
	#jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore my-new.keystore -storepass "password" file.apk alias_name
	rm file.apk
	mv file-aligned.apk file.apk
	echo "[>] file.apk ready!"
	echo "[>] Done!"
}


apk_pull(){
	PACKAGE=$1
	PACKAGE_PATH=`adb shell pm path $PACKAGE | cut -d ":" -f 2`
	# TODO process output of adb shell pm to manage split APKs.
	if [ -z "$PACKAGE_PATH" ]; then
		echo "[>] Sorry, cant find package $PACKAGE"
		echo "[>] Bye!"
		exit
	fi
	NUM_APK=`echo "$PACKAGE_PATH" | wc -l`
	if [ $NUM_APK > 1 ]; then
		SPLIT_DIR=$PACKAGE"_split_apks"
		mkdir -p $SPLIT_DIR 
		echo "[>] Pulling $PACKAGE: Split apks detected!"
		echo "[>] Pulling $NUM_APK apks in $SPLIT_DIR"
	fi
	echo "[>] Pulling $PACKAGE from $PACKAGE_PATH<<<"
	# todo CHECK IF adb cant pull
	PULLED=`adb pull $PACKAGE_PATH $SPLIT_DIR`

	#	We have to combine split APKs into a single APK, for patching. 
	#	.
	#	Decode all the apks
	SPLIT_APKS=($SPLIT_DIR/*)
	for i in "${SPLIT_APKS[@]}"
	do
		echo $i
		APK_NAME=$i
		APK_DIR=${APK_NAME%.apk} # bash 3.x compliant xD
		APKTOOL_DECODE_OPTS="d $APK_NAME -o $APK_DIR"
		APKTOOL_DECODE_CMD="java -jar $APKTOOL_PATH $APKTOOL_DECODE_OPTS"
		apk_decode "$APKTOOL_DECODE_CMD 1>/dev/null"
	done
	#	Walk the extracted APK dirs and copy files and dirs to the base APK dir 
	for i in "${SPLIT_APKS[@]}"
	do
		#echo $i
		APK_NAME=$i
		APK_DIR=${APK_NAME%.apk} # bash 3.x compliant xD
		# skip base.apk
		if [ $APK_DIR == $SPLIT_DIR"/base" ]; then
			continue
		fi
		echo "[-----] APK DIRECTORY: "$APK_DIR
		# Walk each apk dir
		FILES_IN_SPLIT_APK=($APK_DIR/*)
		for j in "${FILES_IN_SPLIT_APK[@]}"
		do
			echo "[.] Split apks file: "$j
			# Skip Manifest, apktool.yml, and the original files dir.
			if [[ $j == *AndroidManifest.xml ]] || [[ $j == *apktool.yml ]] || [[ $j == *original ]]; then
				echo "[-] Skip!"
				echo ""
				continue
			fi
			#	Copy files into the base APK, except for XML files in the res directory
			if [[ $j == */res ]]; then
				echo "[.] /res direcorty found!":
				echo "dollaro j "$j
				echo "splitdir "$SPLIT_DIR
				(cd $j; find . -type f ! -name '*.xml' -exec cp --parents {} ../../base/res/ \; -exec echo [+] Copying res that are not xml {} \;)    
				continue
			fi
			echo "[>] Copying directory cp -R $j in $SPLIT_DIR/base/ ...."
			cp -R $j $SPLIT_DIR"/base/"
		done
	done
	#	Fix public resource identifiers   
	#	Find all resource IDs with name APKTOOOL_DUMMY_xxx in the base dir
	DUMMY_IDS=`grep -r "APKTOOL_DUMMY_" $SPLIT_DIR"/base" | grep -Po "id=\"\K.*?(?=\")" | grep 0x`
	stra=($DUMMY_IDS)
	for j in "${stra[@]}"
	do
		echo "[~] DUMMY_ID_TO_FIX: "$j
		#	Get the dummy name grepping for the resource ID
		DUMMY_NAME=`grep -r "$j" $SPLIT_DIR/base | grep DUMMY | grep -Po "name=\"\K.*?(?=\")"`
		echo "[~] DUMMY_NAME: "$DUMMY_NAME
		#	Get the real resource name grepping for the resource ID in each spit APK
		REAL_NAME=`grep -r "$j" $SPLIT_DIR | grep -v DUMMY | grep -v base | grep name | grep -Po "name=\"\K.*?(?=\")"`
		echo "[~] REAL_NAME: "$REAL_NAME
		# Grep DUMMY_NAME and substitute the real resource name in the base dir
		echo "[~] File of base.apk with the DUMMY_NAME to update:"
		grep -r "\<$DUMMY_NAME\>" $SPLIT_DIR"/base" | grep "\.xml:"
		grep -r "\<$DUMMY_NAME\>" $SPLIT_DIR"/base" | grep "\.xml:" | cut -d ":" -f 1 | xargs sed -i "s/\<$DUMMY_NAME\>/$REAL_NAME/g"
		echo "[~] Updated line:"
		grep -r "\<$REAL_NAME\>" $SPLIT_DIR"/base" | grep "\.xml:" 
		echo "---"
	done

 	#	Disable APK splitting in the base manifest file, if it’s not there already done.        
	echo "[>] Disabling APK splitting..."
	echo "[?] Checking if android:isSplitRequired is set to false..."
	SPLIT_REQUIRED=0
	MANIFEST_PATH="$SPLIT_DIR/base/AndroidManifest.xml"
	readarray -t manifest < $MANIFEST_PATH
	for i in "${manifest[@]}"
	do
		if [[ "$i" == *"android:isSplitRequired=\"false\""* ]]; then
			SPLIT_REQUIRED=1
			echo "[>] android:isSplitRequired already set to false!"
			break
		fi
	done
	if [[ $SPLIT_REQUIRED == 0 ]]; then
		echo "[!] android:isSplitRequired not set to false in the Manifest!"
		echo "[>] Patching base AndroidManifest.xml setting android:isSplitRequired to false.."
		echo "[>] Patching $MANIFEST_PATH"
		sed -i "s/android:isSplitRequired=\"true\"/android:isSplitRequired=\"false\"/g" $MANIFEST_PATH
		echo "[>] Patched !"
	fi

# Set android:extractNativeLibs="true" in the Manifest if you experience any adb: failed to install file.gadget.apk: Failure [INSTALL_FAILED_INVALID_APK: Failed to extract native libraries, res=-2]
	echo "[>] Enabling native libraries extraction if it was set to false..."
	MANIFEST_PATH="$SPLIT_DIR/base/AndroidManifest.xml"
	# if the tag exist and is set to false, set it to true, otherwise do nothing
	sed -i "s/android:extractNativeLibs=\"false\"/android:android:extractNativeLibs=\"true\"/g" $MANIFEST_PATH
	echo "[>] Done!"
	fi

	#	Rebuild the base APK 
	APKTOOL_BUILD_OPTS="b -d $SPLIT_DIR"/base" -o file.apk --use-aapt2"
	APKTOOL_BUILD_CMD="java -jar $APKTOOL_PATH $APKTOOL_BUILD_OPTS"
	apk_build "$APKTOOL_BUILD_CMD"
	mv file.apk single_file.apk
	echo "[>] single_file.apk ready!"
	echo "[>] Bye!"


}

apk_patch(){
	# TODO
}


#####################################################################
#####################################################################
check_apk_tools 

if [ ! -z $1 ]&&[ $1 == "build" ]; then
	if [ -z "$2" ]; then
    	echo "Pass the apk directory name!"
    	echo "./apk build <apk_dir>"
		exit
	fi
#	
# It seems there is a problem with apktool build and manifest attribute android:dataExtractionRules 
# 	: /home/ax/AndroidManifest.xml:30: error: attribute android:dataExtractionRules not found.
# 	W: error: failed processing manifest.
# Temporary workaround: remove the attribute from the Manifest and use Android 9 
#
# Set android:extractNativeLibs="true" in the Manifest if you experience any adb: failed to install file.gadget.apk: Failure [INSTALL_FAILED_INVALID_APK: Failed to extract native libraries, res=-2]
# https://github.com/iBotPeaches/Apktool/issues/1626 - zipalign -p 4 seems to not resolve the issue.
#

	APK_DIR=$2
	APKTOOL_BUILD_OPTS="b -d $APK_DIR -o file.apk --use-aapt2"
	APKTOOL_BUILD_CMD="java -jar $APKTOOL_PATH $APKTOOL_BUILD_OPTS"
	#echo "[>] Building $APK_DIR with $APKTOOL_BUILD_CMD"
	apk_build "$APKTOOL_BUILD_CMD"

elif [ ! -z $1 ]&&[ $1 == "decode" ]; then
	if [ -z "$2" ]; then
    	echo "Pass the apk name!"
    	echo "./apk decode <apkname.apk>"
		exit
	fi
	APK_NAME=$2
	APKTOOL_DECODE_OPTS="d $APK_NAME"
#	APKTOOL_DECODE_OPTS="d -r -s $APK_NAME" # no disass dex
#	APKTOOL_DECODE_OPTS="d -r $APK_NAME" # no decompile res
	APKTOOL_DECODE_CMD="java -jar $APKTOOL_PATH $APKTOOL_DECODE_OPTS"
	apk_decode "$APKTOOL_DECODE_CMD"

elif [ ! -z $1 ]&&[ $1 == "patch" ]; then
	# Frida gadget exposes a frida-server compatible interface, listening on localhost:27042 by default.
	# run as soon as possible: frida -D emulator-5554 -n Gadget
	#
	arm=("armeabi" "armeabi-v7a")
	arm64=("arm64-v8a" "arm64")
	x86=("x86")
	x86_64=("x86_64")
	# supported_arch=("arm" "arm64" "x86" "x86_64")
	supported_arch=("arm" "x86_64" "x86")
	GADGET_VER="15.1.28"
	GADGET_ARM="frida-gadget-15.1.28-android-arm.so.xz"
	GADGET_ARM64="frida-gadget-15.1.28-android-arm64.so.xz"
	GADGET_X86_64="frida-gadget-15.1.28-android-x86_64.so.xz"
	GADGET_X86="frida-gadget-15.1.28-android-x86.so.xz"
	#GADGET_X86_64="frida-gadget-15.2.2-android-x86_64.so.xz"

	#  folder:arch
	#  'armeabi': 'arm',
	#  'armeabi-v7a': 'arm',
    #  'arm64': 'arm64',
    #  'arm64-v8a': 'arm64',
    #  'x86': 'x86',
	#  'x86_64': 'x86_64',


	if [ -z "$2" ]; then
    	echo "Pass the apk name and the arch param!"
    	echo "./apk patch <apkname.apk> --arch arm"
		echo "[>] Bye!"
		exit
	fi
	APK_NAME=$2
	if [ ! -f "$APK_NAME" ]; then
		echo "[!] apk $APK_NAME not found!"
		echo "[>] Bye!"
		exit
	fi

	if [ -z "$3" ]||[ "$3" != "--arch" ]; then
    	echo "Pass the --arch param"
    	echo "./apk patch <apkname.apk> --arch arm"
		echo "[>] Bye!"
		exit
	fi
	if [ -z "$4" ]; then
    	echo "Specify the target CPU architecture"
    	echo "./apk patch <apkname.apk> --arch arm"
		echo "[>] Bye!"
		exit
	fi
	ARCH=$4
	if [[ ! "${supported_arch[*]}" =~ "${ARCH}" ]]; then
		echo "[!] Architecture not supported!"
		echo "[>] Bye!"
		exit
	fi

	if [ -z $5 ]||[ "$5" != "--gadget-conf" ]; then
		echo $5
		echo "Pass the --gadget-conf param"
    	echo "./apk patch <apkname.apk> --arch arm --gadget-conf <file>"
		echo "[>] Bye!"
		exit
	fi
	GADGET_CONF_PATH=$6
	if [ ! -f "$GADGET_CONF_PATH" ]; then
		echo "[!] Gadget configuration json file ($GADGET_CONF_PATH) not found!"
		echo "[>] Bye!"
		exit
	fi

	echo "[>] Injecting Frida gadget for $ARCH in $APK_NAME..."

	if [[ ${ARCH} == "arm"  ]]; then
		GADGET=$GADGET_ARM
		ARCH_DIR="armeabi-v7a"
	elif [[ ${ARCH} == "x86_64" ]]; then
		GADGET=$GADGET_X86_64
		ARCH_DIR="x86_64"
	elif [[ ${ARCH} == "x86" ]]; then
		GADGET=$GADGET_X86
		ARCH_DIR="x86"
	elif [[ ${ARCH} == "arm64" ]]; then
		GADGET=$GADGET_ARM64
		ARCH_DIR="arm64-v8a"
	fi

	FRIDA_SO_XZ="$APK_SH_HOME/$GADGET"

	if [ ! -f "${FRIDA_SO_XZ::-3}" ]; then
		if [ ! -f "$FRIDA_SO_XZ" ]; then
			echo "[!] Frida gadget not present in $APK_SH_HOME"
			echo "[>] Downloading latest frida gadget for $ARCH from github.com..."
			wget https://github.com/frida/frida/releases/download/15.1.28/$GADGET -q --show-progress -P $APK_SH_HOME 
		fi
		unxz "$FRIDA_SO_XZ"
	else
		echo "[>] Frida gadget already present in $APK_SH_HOME"
	fi
	echo "[>] Using ${FRIDA_SO_XZ::-3}"

	APKTOOL_DECODE_OPTS="d $APK_NAME"
	APKTOOL_DECODE_CMD="java -jar $APKTOOL_PATH $APKTOOL_DECODE_OPTS"
	apk_decode "$APKTOOL_DECODE_CMD"

	echo "[>] Placing the frida shared object for $ARCH...."
	APK_DIR=${APK_NAME%.apk} # bash 3.x compliant xD
	mkdir -p "$APK_DIR/lib/$ARCH_DIR/"
	cp ${FRIDA_SO_XZ::-3} $APK_DIR/lib/$ARCH_DIR/libfrida-gadget.so
	if [ ! -z $GADGET_CONF_PATH ]; then
		echo "[>] Placing the specified gadget configuration json file...."
		cp "$GADGET_CONF_PATH" $APK_DIR/lib/$ARCH_DIR/libfrida-gadget.config.so
	fi

	# Inject a System.loadLibrary("frida-gadget") call into the smali,
	# before any other bytecode executes or any native code is loaded.
	# A suitable place is typically the static initializer of the entry point class of the app (e.g. the main application Activity).
	# We have to determine the class name for the activity that is launched on application startup.
	# In Objection this is done by first trying to parse the output of aapt dump badging, then falling back to manually parsing the AndroidManifest for activity-alias tags.
	echo "[>] Searching for a launchable-activity..."
	MAIN_ACTIVITY=`aapt dump badging $APK_NAME | grep launchable-activity | grep -Po "name='\K.*?(?=')"`
	echo "[>] launchable-activity found --> $MAIN_ACTIVITY"
	# TODO: If we dont get the activity, we gonna check out activity aliases trying to manually parse the AndroidManifest.
	# Try to determine the local path for a target class' smali converting the main activity to a path
	MAIN_ACTIVITY_2PATH=`echo $MAIN_ACTIVITY | tr '.' '/'`
	CLASS_PATH="./$APK_DIR/smali/$MAIN_ACTIVITY_2PATH.smali"
	echo "[>] Local path is $CLASS_PATH"
	# NOTE: if the class does not exist it might be a multidex setup, Smali not found in smali directory. Look for _2 _3 etc. 
	#
	# Now, patch the smali, look for the line with the apktool's comment "# direct methods" 
	# Patch the smali with the appropriate loadLibrary call based on wether a constructor already exists or not.
	# If an existing constructor is present, the partial_load_library will be used.
	# If no constructor is present, the full_load_library will be used.
	#
	# Objection checks if there is an existing <clinit> to determine which is the constructor,
	# then they inject a loadLibrary just before the method end.
	#
	# We search for *init> and inject a loadLibrary just after the .locals declaration.
	#
	# <init> is the (or one of the) constructor(s) for the instance, and non-static field initialization.
	# <clinit> are the static initialization blocks for the class, and static field initialization.
	#
	echo "[>] Patching smali..."
	readarray -t lines < $CLASS_PATH
	index=0
	skip=1
	for i in "${lines[@]}"
	do
		# partial_load_library
		if [[ $i == "# direct methods" ]]; then
			if [[   ${lines[$index+1]} == *"init>"* ]]; then
				echo "[>>] A constructor is already present --> ${lines[$index+1]}"
				echo "[>>] Injecting partial load library!"
				# Skip  any .locals and write after
				# Do we have to skip .annotaions? is ok to write before them?
				if [[ ${lines[$index+2]} =~ \.locals* ]]; then
					echo "[>>] .locals declaration found!"
					echo "[>>] Skipping .locals line..."
					skip=2
					echo "[>>] Update locals count..."
					locals=`echo ${lines[$index+2]} | cut -d' ' -f2`
					((locals++))
					lines[$index+2]=".locals $locals"
				else
					echo "[!!!!!!] No .locals found! :("
					echo "[!!!!!!] TODO add .locals line"
				fi
				arr=("${lines[@]:0:$index+1+$skip}") 			# start of the array
				# We inject a loadLibrary just after the locals delcaration.
				# Objection add the loadLibrary call just before the method end.
				arr+=( 'const-string v0, "frida-gadget"')
				arr+=( 'invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V')
				arr+=( "${lines[@]:$index+1+$skip}" ) 		# tail of the array
        		lines=("${arr[@]}")     					# transfer back in the original array.
			else
				echo "[!!!!!!] No constructor found!"
				echo "[!!!!!!] TODO: gonna use the full load library"
				#arr+=('.method static constructor <clinit>()V')
				#arr+=('   .locals 1')
				#arr+=('')
				#arr+=('   .prologue')
				#arr+=('   const-string v0, "frida-gadget"')
				#arr+=('')
				#arr+=('   invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V')
				#arr+=('')
				#arr+=('   return-void')
				#arr+=('.end method')
			fi
		fi
		((index++))
	done
	echo "[>] Writing the pathced smali back..."
	printf "%s\n" "${lines[@]}" > $CLASS_PATH
	
	# Add the Internet permission to the manifest if it’s not there already, to permit Frida gadget to open a socket.
	echo "[?] Checking if Internet permission is present in the manifest..."
	INTERNET_PERMISSION=0
	MANIFEST_PATH="$APK_DIR/AndroidManifest.xml"
	readarray -t manifest < $MANIFEST_PATH
	for i in "${manifest[@]}"
	do
		if [[ "$i" == *"<uses-permission android:name=\"android.permission.INTERNET\"/>"* ]]; then
			INTERNET_PERMISSION=1
			echo "[>] Internet permission is there!"
			break
		fi
	done
	if [[ $INTERNET_PERMISSION == 0 ]]; then
		echo "[!] Internet permission not present in the Manifest!"
		echo "[>] Patching $MANIFEST_PATH"
		arr=("${manifest[@]:0:1}") 			# start of the array
		arr+=( '<uses-permission android:name="android.permission.INTERNET"/>')
		arr+=( "${manifest[@]:2}" ) 		# tail of the array
        manifest=("${arr[@]}")     		# transfer back in the original array.
		echo "[>] Writing the patched manifest back..."
		printf "%s\n" "${manifest[@]}" > $MANIFEST_PATH
	fi

	APKTOOL_BUILD_OPTS="b -d $APK_DIR -o file.apk --use-aapt2"
	APKTOOL_BUILD_CMD="java -jar $APKTOOL_PATH $APKTOOL_BUILD_OPTS"
	#echo "[>] Building $APK_DIR with $APK_BUILD_CMD"
	apk_build "$APKTOOL_BUILD_CMD"
	mv file.apk $APK_DIR.gadget.apk
	echo "[>] $APK_DIR.gadget.apk ready!"
	echo "[>] Bye!"
elif [ ! -z $1 ]&&[ $1 == "pull" ]; then
	if [ -z "$2" ]; then
    	echo "Pass the package name!"
    	echo "./apk pull <com.package.name>"
		exit
	fi
	PACKAGE_NAME=$2
	apk_pull "$PACKAGE_NAME"
else
    echo "./apk build <apk_dir>"
	echo "./apk decode <apk_name.apk>"
	echo "./apk patch <apk_name.apk> --arch arm"
	echo "./apk patch <apk_name.apk> --arch x86_64 --gadget-conf libfrida-gadget.config.so"
	echo "[>] First arg must be build, decode or patch!"
	exit
fi