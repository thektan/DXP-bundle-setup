#!/bin/bash

# -----------------------------------------------------------------------------
# Sets variables to use within script.
# -----------------------------------------------------------------------------

source variables.sh

fetch_dependency () {
	CACHE_DIR=".cache"
	url=$1

	mkdir -p $CACHE_DIR

	md5=$(echo -n "$url" | md5sum | cut -f1 -d' ')

	if [ ! -e $CACHE_DIR/$md5 ]
	then
		wget -q $url -O $CACHE_DIR/$md5
	fi

	echo "$CACHE_DIR/$md5"
}

# --------------------------------------------------------------
# Initializes the server for Liferay DXP.
# --------------------------------------------------------------

echo "================== Extracting bundle archive... ==================="

mkdir $LIFERAY_HOME_PARENT_DIR/temp

BUNDLE_ZIPFILE=`fetch_dependency "http://mirrors.lax.liferay.com/files.liferay.com/private/ee/portal/7.0.10.1/liferay-dxp-digital-enterprise-tomcat-7.0-sp1-20161027112321352.zip"`

unzip -d $LIFERAY_HOME_PARENT_DIR/temp -q "$BUNDLE_ZIPFILE"

rm -rf $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME

mv $LIFERAY_HOME_PARENT_DIR/temp/liferay-* $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME

rm -rf $LIFERAY_HOME_PARENT_DIR/temp

rm -rf $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/work $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat-*/temp $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat-*/work

ln -s `ls $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME | grep "tomcat-"` $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat

echo "==================== Setting up DXP license... ===================="

mkdir $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/deploy/
cp license/* $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/deploy/

echo "=================== Applying configurations... ===================="

cp properties/* $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat/webapps/ROOT/WEB-INF/classes

for PROPERTY in ${PORTAL_EXTRA_PROPERTIES[@]}; do
	echo -e "\n$PROPERTY" >> $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat/webapps/ROOT/WEB-INF/classes/portal-ext.properties
done

mkdir -p $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/osgi/configs

for FILENAME in configs/*; do
	sed "s/indexNamePrefix = .*/indexNamePrefix = $INDEX_NAME/g" $FILENAME > $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/osgi/configs/$(basename "$FILENAME")
done

cp -br tomcat/* $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/tomcat/

echo "======================= Applying fixpack... ======================="

rm -rf $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/

LATEST_PATCHING_TOOL=patching-tool-`curl --silent http://mirrors.lax.liferay.com/files.liferay.com/private/ee/fix-packs/patching-tool/LATEST-2.0.txt`.zip

PATCHING_TOOL_ZIPFILE=`fetch_dependency "http://mirrors.lax.liferay.com/files.liferay.com/private/ee/fix-packs/patching-tool/${LATEST_PATCHING_TOOL}"`

unzip -d $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME -q "$PATCHING_TOOL_ZIPFILE"

chmod u+x $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/*.sh

echo -e "patching.mode=binary\nwar.path=../tomcat/webapps/ROOT/\nglobal.lib.path=../tomcat/lib/ext/\nliferay.home=../" > $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/default.properties

$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patching-tool.sh auto-discovery ..${PATCHING_DIR}
$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patching-tool.sh revert

rm -fr $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patches/*

FIXPACK_ZIPFILE=`fetch_dependency "http://mirrors.lax.liferay.com/files.liferay.com/private/ee/fix-packs/7.0.10/${FIX_PACK}-7010.zip"`

cat "$FIXPACK_ZIPFILE" > $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patches/patch.zip

PATCH_INFO=`$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patching-tool.sh info | grep '\[ x\]\|\[ D\]\|\[ o\]\|\[ s\]'`

if [[ ! -z ${PATCH_INFO} ]]
then
	echo "Unable to patch:"
	echo "${PATCH_INFO}"

	rm /tmp/peek_redeploy.lock

	exit 0
fi

$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patching-tool.sh install
$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/patching-tool/patching-tool.sh update-plugins

rm -fr $LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/osgi/state

echo "====================== Deploying plugins... ======================="

for MODULE in ${DEPLOYABLE_URL_MODULES[@]}; do
	filename=$(basename "$MODULE")

	wget "$MODULE" -O "$filename"

	mv -v "$filename" "$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/osgi/modules/${filename/-[0-9]\.[0-9]\.[0-9]\.jar/.jar}"
done

for MODULE in ${DEPLOYABLE_PORTAL_MODULES[@]}; do
	cd $PORTAL_REPO_DIR/modules/$MODULE

	if [ -e $PORTAL_REPO_DIR/modules/$MODULE/build.xml ]
	then
		ant "-Dapp.server.deploy.dir=$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME/deploy" deploy
	else
		sudo $PORTAL_REPO_DIR/gradlew --no-daemon "-Dliferay.home=$LIFERAY_HOME_PARENT_DIR/$DESIRED_HOME_DIR_NAME" deploy
	fi
done

echo "============================== Done. =============================="
