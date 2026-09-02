# Debian pro ZyXEL NSA320

Projekt připraví USB disk s Debianem pro zařízení ZyXEL NSA320/Kirkwood.
Spouští se na počítači nebo v Termuxu a přes SSH provede operace na serveru,
ke kterému je USB disk fyzicky připojen.

## Požadavky

- Bash, `openssh`, `wget` a `tar` na klientovi
- SSH přístup jako `root` (doporučený je klíč, ne heslo)
- `parted`, `partprobe`, `mkfs.ext4`, `mount`, `tar` a `dd` na serveru
- záloha všech dat na cílovém disku

## Použití

```sh
chmod +x build.sh
./build.sh --server 192.168.1.20 --ssh-key ~/.ssh/server --device /dev/sdb
```

Skript nikdy nevybírá disk automaticky. Bez `--yes` vyžaduje na vzdáleném
serveru zadání celé cesty k cílovému zařízení jako ochranu proti překlepu.
Instalace přepíše partition table a vytvoří jeden oddíl ext4 s rootfs.
U-Boot se standardně nemění. Tato operace je destruktivní.

Lokální soubory lze dodat bez stahování:

```sh
./build.sh --device /dev/sdb \
  --rootfs ./Debian-5.6.7-kirkwood-tld-1-rootfs-bodhi.tar.bz2 \
  --uboot ./u-boot.kwb
```

URL obrazů a výchozí hodnoty lze nastavit proměnnými `ROOTFS_URL`, `UBOOT_URL`,
`SERVER`, `REMOTE_USER`, `SSH_KEY` a `WORKDIR`. Výchozí URL nejsou nastavené,
protože původní odkazy na `doozan.com` již vracejí 404. Před použitím ověřte,
že stažené obrazy odpovídají konkrétnímu modelu a bootloaderu.

U-Boot se standardně do disku nezapisuje. Volbu `--write-uboot` použijte jen
s obrazem ověřeným pro konkrétní NSA320; běžný systém s U-Bootem v NAND tuto
volbu nepotřebuje:

```sh
./build.sh --device /dev/sdb --rootfs ./rootfs.tar.bz2 \
  --uboot ./u-boot.kwb --write-uboot
```

## Boot po instalaci

1. Bezpečně odpojte USB disk a připojte ho k NSA320.
2. Zapněte zařízení a sledujte konzoli zařízení.
3. Pokud firmware USB nespouští automaticky, nastavte bootovací parametry
   podle dokumentace k vašemu U-Bootu.

Projekt neposkytuje ani negarantuje konkrétní U-Boot obraz. Používejte pouze
obraz určený pro přesný model zařízení.
