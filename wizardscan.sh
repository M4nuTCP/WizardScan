#!/bin/bash

#--------Colores-----------------
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"
turquoiseColour="\e[0;36m\033[1m"
grayColour="\e[0;37m\033[1m"

# Capturar ctrl+c
function ctrl_c(){
    echo -e "\n\n${redColour}[!] Saliendo...${endColour}\n"
    exit 1 
}

trap ctrl_c INT

function main(){
    dominio=$1

    echo -en "\n${greenColour}[+] Nombre de la carpeta:${endColour} "
    read carpeta

    base_dir=$(pwd)
    subdominios_dir="$base_dir/$carpeta/subdominios"
    nmap_dir="$base_dir/$carpeta/NmapScan"
    wpscan_dir="$base_dir/$carpeta/wpscan"

    mkdir -p "$subdominios_dir"
    mkdir -p "$nmap_dir"
    mkdir -p "$wpscan_dir"
    cd "$subdominios_dir"

    echo -e "\n${blueColour}[*] Iniciando busqueda de dominios${endColour}\n"

    curl -s https://crt.sh/\?q\=$dominio\&output\=json | jq . | grep name | cut -d":" -f2 | grep -vE "CN=|=|@|CIF" | cut -d'"' -f2 | awk '{gsub(/\\n/,"\n");}1;' | sort -u > subdominiosList.txt

    cat subdominiosList.txt
    echo -e "\n${greenColour}[·] Archivo subdominiosList.txt creado exitosamente${endColour}\n"

    echo -e "\n${blueColour}[*] Iniciando busquedas de Ips relacionadas${endColour}\n"
    for i in $(cat subdominiosList.txt); do host $i | grep "has address" | cut -d" " -f4; done 2>/dev/null | sort -u > ips.txt

    cat ips.txt
    echo -e "\n${greenColour}[·] Archivo ips.txt creado exitosamente${endColour}\n"

    echo -e "\n${blueColour}[*] Iniciando busqueda de Ips relacionadas a los subdominios encontrados${endColour}\n"
    for i in $(cat subdominiosList.txt); do host $i | grep "has address" | awk '{print $1, $4}'; done 2>/dev/null | sort -u > subdominios_ips.txt

    cat subdominios_ips.txt
    echo -e "\n${greenColour}[·] Archivo subdominios_ips.txt creado exitosamente${endColour}\n"

    echo -en "${purpleColour}[+]¿Quieres iniciar el escaneo con Nmap? (s/n): ${endColour}"
    read respuesta

    if [[ $respuesta == "s" || $respuesta == "S" ]]; then
        cd "$nmap_dir"
        if ! command -v nmap &> /dev/null; then
            echo -en "${redColour}[!]${endColour} ${grayColour}Instalando nmap...${endColour}"
            sudo apt install -y nmap
            echo -en "${redColour}[!]${endColour} ${grayColour}Instalado con éxito${endColour}"
        fi
        nmap_scan "$subdominios_dir/ips.txt"
    fi

    detect_wordpress "$subdominios_dir/subdominiosList.txt"
    tree .
}

function nmap_scan() {
    ips_file=$1

    echo -en "${purpleColour}[+] ¿Qué min-rate quieres?:${endColour}  "
    read minrate

    echo -e "\n${redColour}[!] Esto puede tardar unos minutos...${endColour}"

    if [[ ! -f "$ips_file" ]]; then
        echo -e "\n${redColour}[!] Error: No se encontró el archivo $ips_file${endColour}\n"
        exit 1
    fi

    while IFS= read -r ip; do
        echo -e "\n${blueColour}[+] Escaneando $ip${endColour}"
        nmap -p- --open --min-rate $minrate -n -Pn $ip -oN target_$ip >/dev/null 2>&1
        ports=$(grep '^[0-9]' target_$ip | cut -d '/' -f1 | sort -u | xargs | tr ' ' ',')
        rm target_$ip
        echo -e "\n${greenColour}[+] Fase del escaneo Escaneo${endColour} $ip ${greenColour}-> 40%${endColour} \n"
        if [ -n "$ports" ]; then
            nmap -p$ports -sCV --min-rate $minrate -vvv -n -Pn $ip -oN nmap_$ip.txt 2>/dev/null
        else
            echo "No se encontraron puertos abiertos en $ip"
        fi
    done < "$ips_file"
}

function detect_wordpress() {
    subdominios_file="$1"

    wordpress_sites=()

    if [[ ! -f "$subdominios_file" ]]; then
        echo -e "\n${redColour}[!] Error: No se encontró el archivo $subdominios_file${endColour}\n"
        exit 1
    fi

    while IFS= read -r subdomain; do
        wp_content=$(curl -s -o /dev/null -w "%{http_code}" "https://$subdomain/wp-content/")
        if [[ "$wp_content" == "200" || "$wp_content" == "301" ]]; then
            wordpress_sites+=($subdomain)
        fi
    done < "$subdominios_file"

    if [[ ${#wordpress_sites[@]} -gt 0 ]]; then
        echo -e "\n${redColour}[!] Se ha detectado WordPress en los siguientes subdominios:${endColour}\n"
        for site in "${wordpress_sites[@]}"; do
            echo -e "\t $site"
        done

        echo -en "\n${purpleColour}[+] ¿Quieres iniciar el escaneo con WPScan? Pulsa 'c' para configurar API key (s/n/c): ${endColour}"
        read wp_respuesta

        if [[ $wp_respuesta == "s" || $wp_respuesta == "S" ]]; then
            if ! command -v wpscan &> /dev/null; then
                echo -en "${redColour}[!]${endColour} Instalando WPScan..."
                sudo apt install -y wpscan
                echo -en "${redColour}[!]${endColour} Instalado con éxito\n"
            fi
            scan_wordpress
        elif [[ $wp_respuesta == "c" || $wp_respuesta == "C" ]]; then
            echo -en "\n${greenColour}[+] Introduce tu WPScan API key: ${endColour}"
            read api_key
            if ! command -v wpscan &> /dev/null; then
                echo -en "${redColour}[!]${endColour} Instalando WPScan..."
                sudo apt install -y wpscan
                echo -en "${redColour}[!]${endColour} Instalado con éxito\n"
            fi
            scan_wordpress_with_key $api_key
        else
            ctrl_c
        fi
    else
        echo -e "\n${greenColour}[+] No se detectaron sitios WordPress${endColour}"
    fi
}

function scan_wordpress() {
    cd "$wpscan_dir"
    for site in "${wordpress_sites[@]}"; do
        echo -e "\n${blueColour}[+] Escaneando WordPress en ${endColour}$site"
        wpscan --url "https://$site/" -e vp,u --random-user-agent --disable-tls-checks | tee wpscan_$site.txt
    done
}

function scan_wordpress_with_key() {
    api_key=$1
    cd "$wpscan_dir"
    for site in "${wordpress_sites[@]}"; do
        echo -e "\n${blueColour}[+] Escaneando WordPress en ${endColour}$site ${blueColour}con API key${endColour}"
        wpscan --api-token $api_key --url "https://$site/" -e vp,u --random-user-agent --disable-tls-checks | tee wpscan_$site.txt
    done
}

function helpPanel() {
    echo -e "\n${yellowColour}[!] Uso: $0 -u <dominio>${endColour}"
    echo -e "\n\t${yellowColour}-u:${endColour} Especificar el dominio a escanear"
    echo -e "\t${yellowColour}Ejemplo:${endColour} <scanwizard -u ejemplo.com>"
    exit 1
}

declare parameter_counter=0

while getopts "u:h" arg; do
    case $arg in 
        u) dominio=$OPTARG; let parameter_counter+=1;;
        h) helpPanel;;
    esac
done 

if [ $parameter_counter -eq 1 ]; then 
    main $dominio
else
    helpPanel
fi

