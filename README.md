# Format Disk Tool

GUI for å formatere disker og USB-minnepinner i **FAT16**, **FAT32** eller **NTFS** på Windows.

## Kjøre

Dobbeltklikk `Start-FormatDiskTool.bat` (eller høyreklikk `FormatDiskTool.ps1` → "Kjør med PowerShell").

Programmet ber automatisk om administrator-rettigheter - godta UAC-vinduet.

## Bruk

1. Velg disk i nedtrekkslista (system-drevet vises ikke).
2. Velg format: FAT16, FAT32 eller NTFS.
3. Skriv eventuelt et volumnavn (maks 32 tegn).
4. Hak av/på **Hurtigformat** (av = full format, tregere, nuller hele disken).
5. Klikk **FORMATER**.
6. Bekreft to ganger: ja/nei-advarsel + tast inn drevbokstaven.

## Sikkerhetsvakter

- **System-drevet** (`C:` e.l.) ekskluderes alltid - kan ikke velges.
- Krever **administrator**.
- **Dobbel bekreftelse**: advarsel + manuell inntasting av drevbokstav.
- **FAT16 på volum over 4 GB**: GUI-en tilbyr å lage en 3,9 GB FAT16-partisjon i
  stedet (sletter hele disken, resten blir ubrukt) - i stedet for bare å blokkere.

## Filsystem-grenser (Windows)

| Format | Maks volum | Maks filstørrelse | Merknad |
|--------|-----------|-------------------|---------|
| FAT16  | 4 GB      | 2 GB              | Kun små volumer/eldre enheter |
| FAT32  | 32 GB*    | 4 GB              | *Windows `Format-Volume` nekter > 32 GB |
| NTFS   | 256 TB+   | ~16 TB            | Standard for store disker |

> FAT32 på volumer over 32 GB krever tredjepartsverktøy - Windows sin innebygde
> formatering (som dette verktøyet bruker) støtter det ikke.

## Advarsel

Formatering sletter **alt** innhold på det valgte volumet permanent. Sjekk at du
har valgt riktig disk før du bekrefter.
