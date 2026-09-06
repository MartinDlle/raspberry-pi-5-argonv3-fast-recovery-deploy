# Raspberry Pi 5 + Argon ONE V3 — Recovery NVMe sans écran

Ce dépôt met en place un système de **recovery headless** pour :

- Raspberry Pi 5
- Argon ONE V3 M.2 NVMe
- système principal sur NVMe
- Raspberry Pi OS Lite 64-bit de secours sur microSD
- administration uniquement en SSH

Une fois installé :

```text
NVMe principal
    |
    | sudo recovery
    v
microSD Recovery
    |
    | sudo reset-pi --erase
    v
Raspberry Pi OS neuf sur le NVMe
```

Aucun écran, clavier ou souris n'est nécessaire.

## Ce que fait le système

`sudo recovery` :

- vérifie qu'une microSD est présente ;
- demande au Raspberry Pi 5 de démarrer **une seule fois** sur la SD ;
- redémarre.

`sudo reset-pi --check` :

- vérifie que l'on est bien sur la microSD ;
- identifie le NVMe par modèle, numéro de série et taille ;
- vérifie l'image Raspberry Pi OS ;
- n'écrit rien sur le NVMe.

`sudo reset-pi --erase` :

- demande le nom du nouvel utilisateur ;
- demande deux confirmations avant effacement ;
- efface et réinstalle Raspberry Pi OS Lite 64-bit ;
- agrandit la partition au NVMe complet ;
- restaure la clé SSH autorisée ;
- restaure l'identité SSH du Raspberry Pi ;
- conserve le mot de passe `sudo` du compte source ;
- conserve le hostname ;
- réinstalle Argon ONE V3 et la configuration du ventilateur ;
- réinstalle la commande `recovery` ;
- redémarre automatiquement sur le NVMe.

> **Attention :** `reset-pi --erase` efface entièrement le NVMe cible.

---

## 1. Préparer la microSD

Avec Raspberry Pi Imager, installer :

- **Raspberry Pi OS Lite 64-bit**
- hostname conseillé : `pi-recovery`
- utilisateur conseillé : `recovery`
- SSH activé
- authentification par clé SSH recommandée
- Ethernet recommandé pour le Recovery

Insérer ensuite la microSD dans le Pi.

---

## 2. Vérifier le bootloader du Pi 5

Sur le système principal NVMe :

```bash
sudo rpi-eeprom-config
```

Pour un Argon ONE V3 avec NVMe, la configuration utilisée et testée par ce projet est :

```text
PCIE_PROBE=1
PSU_MAX_CURRENT=5000
POWER_OFF_ON_HALT=1
BOOT_ORDER=0xf416
```

`BOOT_ORDER=0xf416` est lu de droite à gauche :

```text
6 = NVMe
1 = microSD
4 = USB
f = recommencer
```

Le NVMe reste donc prioritaire.

Ce dépôt ne modifie pas automatiquement l'EEPROM. Si nécessaire :

```bash
sudo rpi-eeprom-config --edit
```

Puis redémarrer.

---

## 3. Installer la commande `recovery` sur le NVMe

Depuis le dépôt, sur le système principal :

```bash
sudo ./install-main.sh
```

Vérifier :

```bash
sudo recovery --check
```

Puis tester le démarrage one-shot sur la SD :

```bash
sudo recovery
```

Se reconnecter :

```bash
ssh recovery@pi-recovery.local
```

Le mécanisme one-shot du Raspberry Pi 5 est automatiquement effacé après son utilisation ; le prochain reboot revient donc au `BOOT_ORDER` permanent.

---

## 4. Copier ce dépôt sur la microSD Recovery

Par exemple depuis ton ordinateur :

```bash
scp -r pi5-argon-v3-recovery recovery@pi-recovery.local:~/
```

Puis :

```bash
ssh recovery@pi-recovery.local
cd ~/pi5-argon-v3-recovery
```

---

## 5. Télécharger l'image Raspberry Pi OS Lite

Récupère le SHA-256 de la version Raspberry Pi OS Lite 64-bit que tu souhaites utiliser depuis la page officielle Raspberry Pi.

Puis :

```bash
sudo ./scripts/download-image.sh --sha256 TON_SHA256
```

Le fichier sera enregistré dans :

```text
/opt/pi-recovery/images/raspios-lite-arm64.img.xz
```

Le SHA-256 validé est conservé séparément et sera revérifié avant chaque reset.

Pour utiliser une image déjà téléchargée :

```bash
sudo ./scripts/download-image.sh \
  --file /chemin/vers/raspios.img.xz \
  --sha256 TON_SHA256
```

---

## 6. Initialiser le Recovery

Le NVMe doit encore contenir ton système source à ce moment-là.

Exemple si le compte actuel est `martin` :

```bash
sudo ./install-recovery.sh --source-user martin
```

Le script :

- vérifie qu'il tourne sur la microSD ;
- détecte `/dev/nvme0n1` ;
- installe les dépendances ;
- installe le support Argon ONE V3 sur le Recovery ;
- monte le NVMe en lecture seule ;
- sauvegarde :
  - `authorized_keys`
  - les clés hôte SSH
  - le hash du mot de passe
  - UID/GID
  - hostname
  - timezone
  - configuration Argon
  - modèle, série et taille du NVMe
- installe `/usr/local/sbin/reset-pi`.

Le coffre est stocké sous :

```text
/opt/pi-recovery/backup/
```

> Ce dossier contient des données sensibles, notamment le hash du mot de passe et les clés privées SSH du serveur. Il est protégé en lecture root et ne doit pas être publié.

---

## 7. Vérifier avant un reset

```bash
sudo reset-pi --check
```

Le résultat doit notamment contenir :

```text
[ OK ] Recovery exécuté depuis la microSD
[ OK ] Modèle NVMe confirmé
[ OK ] Numéro de série NVMe confirmé
[ OK ] Taille NVMe confirmée
[ OK ] SHA-256 correct
[ OK ] Coffre Recovery complet
[ OK ] BOOT_ORDER : 0xf416
```

Aucun octet n'est écrit avec `--check`.

---

## 8. Réinitialiser le NVMe

```bash
sudo reset-pi --erase
```

Le script demandera par exemple :

```text
Nom du nouvel utilisateur [martin] : admin
```

Puis deux confirmations explicites.

Après réinstallation :

```bash
ssh admin@pi5.local
```

Le mot de passe `sudo` sera celui du compte source sauvegardé, mais associé au nouveau nom d'utilisateur.

---

## 9. Sortir du Recovery sans réinitialiser

```bash
sudo reboot
```

Le Pi revient normalement au NVMe grâce au `BOOT_ORDER=0xf416`.

---

## 10. Mettre à jour l'image de réinstallation

Télécharger une nouvelle image et fournir son SHA-256 officiel :

```bash
sudo ./scripts/download-image.sh --sha256 NOUVEAU_SHA256
```

Puis :

```bash
sudo reset-pi --check
```

---

## Arborescence installée sur la microSD

```text
/opt/pi-recovery/
├── backup/
│   ├── argon/
│   │   └── argononed.conf
│   ├── ssh/
│   │   ├── authorized_keys
│   │   └── hostkeys/
│   ├── user/
│   │   ├── user.passwd-hash
│   │   └── user.uidgid
│   └── system/
│       ├── hostname
│       ├── timezone
│       ├── default_username
│       ├── nvme.model
│       ├── nvme.serial
│       ├── nvme.size_bytes
│       └── image.sha256
├── images/
│   └── raspios-lite-arm64.img.xz
└── scripts/
    ├── argon1.sh
    ├── recovery
    └── reset-pi
```

---

## Dépannage

### Vérifier sur quel disque le système tourne

```bash
findmnt -no SOURCE /
```

Recovery :

```text
/dev/mmcblk0p2
```

NVMe :

```text
/dev/nvme0n1p2
```

### Le Recovery ne répond pas immédiatement en SSH

Attendre quelques secondes : le réseau peut être disponible avant que `sshd` ait terminé son démarrage.

### Message `LC_CTYPE=UTF-8`

C'est généralement une locale transmise par le client SSH macOS qui n'existe pas sur Raspberry Pi OS. Ce message n'empêche pas le Recovery de fonctionner.

### Wi-Fi bloqué par rfkill

Configurer le pays Wi-Fi :

```bash
sudo raspi-config
```

Pour un serveur Recovery, Ethernet reste recommandé.

### Vérifier Argon

```bash
systemctl status argononed.service --no-pager
```

Avec le script Argon actuellement utilisé sur Raspberry Pi OS, le ventilateur et le bouton sont gérés par `argononed.service`.

---

## Références officielles

- Raspberry Pi bootloader / NVMe / `BOOT_ORDER` :
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
- Raspberry Pi 5 `set_reboot_order` / `vcmailbox` :
  https://www.raspberrypi.com/documentation/computers/config_txt.html
- Raspberry Pi OS cloud-init :
  https://www.raspberrypi.com/news/cloud-init-on-raspberry-pi-os/
- Argon ONE V3 :
  https://wiki.argon40.com/en/Product_Guides/ONE_V3/Ubuntu_ArgonONE

## Licence

MIT — à utiliser à tes risques. Toujours conserver une sauvegarde des données importantes avant un reset.
