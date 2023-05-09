#!/usr/bin/env sh

# SPDX-License-Identifier: BSD-2-Clause
# 
# Copyright (c) 2023 Vincent DEFERT. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions 
# are met:
# 
# 1. Redistributions of source code must retain the above copyright 
# notice, this list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright 
# notice, this list of conditions and the following disclaimer in the 
# documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
# POSSIBILITY OF SUCH DAMAGE.

# Lists or downloads/updates documents from WCH's web sites (both the
# Chinese and English ones).

# Execute without argument for help.

# === TODO customise to your liking ====================================
# This is the directory under which all documents must be downloaded.
# You may specify subdirectories when invoking updateDocuments
# => SEE BOTTOM OF SCRIPT.
mcuDocRoot='/home/vincent/doc+tools/mcu'

checkPackage() {
    local p="$1"
    local r='1'
    
    if which xbps-install 1> /dev/null 2> /dev/null; then
        if [ -z "$(xbps-query -l | grep "^ii ${p}-")" ]; then
            r='0'
        fi
    elif which dpkg 1> /dev/null 2> /dev/null; then
        if [ -z "$(dpkg -l | grep "^ii[[:space:]]*${p}[[:space:]]")" ]; then
            r='0'
        fi
    fi
    
    echo -n "${r}"
}

# Set requiredPackages according to distribution ID
case "$(grep ^ID= /etc/os-release 2> /dev/null | cut -d '"' -f 2)" in
void)
    requiredPackages='wget tidy5 xmlstarlet'
    ;;

*)
    requiredPackages='wget tidy xmlstarlet'
    ;;
esac

# Check that all required packages have been installed
pkgOK='y'

for p in ${requiredPackages}; do
    if [ $(checkPackage "${p}") -eq 0 ]; then
        echo "FATAL: package ${p} must be installed!" 1>&2
        pkgOK='n'
    fi
done

if [ "${pkgOK}" = 'n' ]; then
    exit 1
fi

# Determine run mode
runMode='help'

case "$1" in
dry-run)
    runMode='dry-run'
    ;;

list)
    runMode='list'
    ;;

update)
    runMode='update'
    ;;
esac

if [ "${runMode}" = 'help' ]; then
    cat <<EOF
Usage: $(basename $0) <runMode>
with runMode being one of:

- dry-run: lists the actions which would be performed on each file if 
the command was run in 'update' mode. Only useful for debugging.

- list: lists the files which would be updated if the command was run
in 'update' mode.

- update: updates all local files for which a most recent version is
available online, both from http://wch-ic.com and http.//www.wch.cn.

- help: displays this message.
EOF
    exit 2
fi

listFiles() {
    local language="$1"
    local keyword="$2"
    local searchUrl='http://wch'
    
    if [ "${language}" = 'en' ]; then
        searchUrl="${searchUrl}-ic.com"
    else
        searchUrl="${searchUrl}.cn"
    fi
    
    searchUrl="${searchUrl}/search?t=downloads&q=${keyword}"
    
    wget -q -O - ${searchUrl} | \
        tidy --quiet yes --show-errors 0 --show-warnings no --quote-ampersand yes --numeric-entities yes --output-xml yes | \
        xml sel --text -t -m "//tr[@class='search-downloads-tr-body']" -i "count(td)= 4" -v "td[position()=4]" -v "',${language},'" -v "td[position()=1]/a/@href" -n
}

compareDates() {
    local d1="$(echo "$1" | tr -d '-')"
    local d2="$(echo "$2" | tr -d '-')"
    local r
    
    if [ ${d1} -eq ${d2} ]; then
        r='eq'
    elif [ ${d1} -lt ${d2} ]; then
        r='lt'
    else
        r='gt'
    fi
    
    echo -n "${r}"
}

downloadFile() {
    local newFileRecord="$1"
    local destDir="$2"
    local listType="$3"
    local fileList="$4"
    
    local newFileDate="$(echo "${newFileRecord}" | cut -d , -f 1)"
    local language="$(echo "${newFileRecord}" | cut -d , -f 2)"
    local pageUrl="$(echo "${newFileRecord}" | cut -d , -f 3)"
    
    local baseName="$(echo "${pageUrl}" | sed 's/.*\/\([^/]*\)_.*\.html/\1/')"
    local suffix="$(echo "${pageUrl}" | sed 's/.*\/[^/]*_\(.*\)\.html/\1/' | tr '[:upper:]' '[:lower:]')"
    local destFile="${baseName}"
    local download='y'
    local action='Updating'
    
    if [ "${suffix}" = 'pdf' ]; then
        destFile="${destFile}-${language}.${suffix}"
    else
        destFile="${destFile}.${suffix}"
    fi
    
    local localFile="${mcuDocRoot}/${destDir}/${destFile}"
    
    local currentFileDate="$(stat -L -c %y ${localFile} 2> /dev/null | cut -d ' ' -f 1)"
    
    if [ -n "${currentFileDate}" ]; then
        if [ "$(compareDates ${newFileDate} ${currentFileDate})" != 'gt' ]; then
            download='n'
            action='Skipping'
        fi
    fi
    
    if [ "${download}" = 'y' ]; then
        case "${listType}" in
        'blacklist')
            if [ "${suffix}" = 'exe' ]; then
                # Windows .exe are undesirable under Linux, unless explicitly whitelisted.
                download='n'
                action='Ignoring'
            elif [ $(expr match "${fileList}" ".*|${baseName}.${suffix}|.*") -ne 0 ]; then
                # expr echoes a non-zero value if the regexp matches
                download='n'
                action='Blacklisting'
            fi
            ;;
        'whitelist')
            if [ $(expr match "${fileList}" ".*|${baseName}.${suffix}|.*") -eq 0 ]; then
                # expr echoes a non-zero value if the regexp matches
                download='n'
            else
                action='Whitelisting'
            fi
            ;;
        esac
    fi
    
    case "${runMode}" in
    update)
        if [ "${download}" = 'y' ]; then
            echo "Updating ${destDir}/${destFile}" 1>&2
            wget -q -O "${localFile}" $(wget -q -O - ${pageUrl} | \
                tidy --quiet yes --show-errors 0 --show-warnings no --quote-ampersand yes --numeric-entities yes --output-xml yes | \
                xml sel --text -t -m "//a[contains(@class,'btn-wch-download')]" -v "@href")
            # Fixes a bug in date conversion between different time zones
            touch "${localFile}"
        fi
        ;;
    
    list)
        if [ "${download}" = 'y' ]; then
            echo "${destDir}/${destFile}" 1>&2
        fi
        ;;
    
    dry-run)
        echo "${action} ${destDir}/${destFile}" 1>&2
        ;;
    esac
}

updateDocuments() {
    local keyword="$1"
    local docDir="$2"
    local listType="$3"
    local fileList="$4"
    local record
    local language
    
    for language in en cn; do
        listFiles "${language}" "${keyword}" | while IFS="\n" read record; do
            downloadFile "${record}" "${docDir}" "${listType}" "${fileList}"
        done
    done
}

# Define black-listed files:

# 1. Generic documentation
blacklist='|PACKAGE.pdf||PRODUCT_GUIDE.pdf||SCHPCB.zip|'
# 2. Programming software and related files
blacklist="${blacklist}|WCH-LinkUserManual.pdf||WCH-LinkSCH.pdf||WCHISPTool_CMD.zip||WCHISPTool_Setup.exe||WCH-LinkUtility.zip||WCH_InSystemProgramTool_V330.exe|"
# 3. Windows-only stuff (e.g. USB drivers)
blacklist="${blacklist}|WCHBleLib_MultiOS.zip||CH372DRV.zip||WCHIOT.zip|"
# 4. Apple-only stuff
blacklist="${blacklist}|BLE_OTA_iOS.zip||CH372DRV.zip||CH37X_MAC.zip|"
# 5. Android-only stuff
blacklist="${blacklist}|BLE_OTA_Android.zip||WCH_Mesh_Android.zip||CH37X_ANDROID.zip|"
# 6. Alias of CH32V307DS0.pdf
blacklist="${blacklist}|CH32V20x_30xDS0.pdf|"
# For some reason, the CH32F20x are associated to CH32Vxxx...
riscvBlacklist="${blacklist}|CH32F20xDS0.pdf|"

# === TODO customise to your liking ====================================
# First argument is the search string on WCH's websites.
# Second argument is where to store documents found (under ${mcuDocRoot}).
# Third argument is 'blacklist' or 'whitelist'.
# Fourth argument is the black- or white-list itself.

# Note: Some files may be incorrectly categorised on WCH's website.
# For instance, if you search for CH32V and see a CH32F... file among
# the results, it may be caused by improper categorisation rather than
# a bug (perform a search on the web site to check). Unfortunately,
# there's nothing to be done against such errors.

updateDocuments 'CH32V' "risc-v/wch/CH32Vxxx" 'blacklist' "${riscvBlacklist}"
updateDocuments 'CH569' "risc-v/wch/CH56x" 'blacklist' "${riscvBlacklist}"
updateDocuments 'CH573' "risc-v/wch/CH57x" 'blacklist' "${riscvBlacklist}"
updateDocuments 'CH583' "risc-v/wch/CH58x" 'blacklist' "${riscvBlacklist}|CH592DS1.pdf|"
updateDocuments 'CH592' "risc-v/wch/CH59x" 'blacklist' "${riscvBlacklist}"

updateDocuments 'CH32F' "arm/wch" 'blacklist' "${blacklist}"
