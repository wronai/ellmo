# Ellmo - Flutter Voice Assistant z Ollama

Kompletny system asystenta głosowego zbudowany z Flutter, integrujący się z Ollama i modelem Mistral. Obsługuje rozpoznawanie mowy (STT), syntezę mowy (TTS) i automatyczne uruchamianie przy starcie systemu.

## 🎯 Funkcje

- **Rozpoznawanie mowy** - Słuchanie poleceń głosowych
- **Synteza mowy** - Odpowiedzi głosowe
- **Integracja z Ollama** - AI model Mistral
- **Autostart** - Uruchamianie przy starcie systemu
- **Uniwersalność** - Działa na Raspberry Pi, Radxa, desktopach z Fedora/Ubuntu
- **Konfigurowalność** - Łatwa zmiana ustawień
- **Interfejs graficzny** - Nowoczesny interfejs Flutter

## 🔧 Wymagania systemowe

### Obsługiwane systemy:
- **Raspberry Pi** (Raspberry Pi OS)
- **Radxa** (Ubuntu/Debian)
- **Fedora** (wszystkie wersje)
- **Ubuntu/Debian** (18.04+)
- **Arch Linux**

### Minimalne wymagania sprzętowe:
- **RAM**: 2GB (4GB zalecane)
- **Procesor**: ARM64/x64
- **Miejsce na dysku**: 5GB wolnego miejsca
- **Audio**: Mikrofon i głośniki/słuchawki

## 🚀 Instalacja

### Szybka instalacja (jeden skrypt)

```bash
# Pobierz installer
wget https://raw.githubusercontent.com/wronai/ellmo/main/install.sh
chmod +x install.sh

# Uruchom instalację
./install.sh
```

### Instalacja manualna

1. **Klonowanie repozytorium**
```bash
git clone https://github.com/wronai/ellmo.git
cd ellmo
```

2. **Uruchomienie instalatora**
```bash
chmod +x install.sh
./install.sh
```

### Co instaluje skrypt:

1. **Zależności systemowe**:
   - Flutter SDK
   - Ollama
   - Python3 z bibliotekami audio
   - Biblioteki GTK dla Linux Desktop
   - ALSA/PulseAudio

2. **Aplikacja Flutter**:
   - Kompilacja dla platformy Linux
   - Konfiguracja platform channels
   - Handler audio w Pythonie

3. **Konfiguracja systemowa**:
   - Usługa systemd
   - Autostart
   - Uprawnienia audio
   - Desktop entry

## 📋 Użytkowanie

### Pierwsze uruchomienie

Po instalacji system automatycznie:
1. Uruchomi Ollama
2. Pobierze model Mistral
3. Skonfiguruje audio
4. Uruchomi aplikację

### Komendy głosowe

**Słowa aktywujące**:
- "Hey Assistant" (angielski)
- "Asystent" (polski)

**Przykłady poleceń**:
- "Hey Assistant, jaka jest pogoda?"
- "Asystent, opowiedz żart"
- "Hey Assistant, what time is it?"

### Zarządzanie usługą

```bash
# Sprawdzenie statusu
sudo systemctl status ellmo

# Uruchomienie
sudo systemctl start ellmo

# Zatrzymanie
sudo systemctl stop ellmo

# Restart
sudo systemctl restart ellmo

# Logi
journalctl -u ellmo -f
```

### Skrypt narzędziowy

```bash
# Skopiuj skrypt utils.sh do /usr/local/bin
sudo cp utils.sh /usr/local/bin/voice-assistant
sudo chmod +x /usr/local/bin/voice-assistant

# Użycie
voice-assistant start      # Uruchom usługę
voice-assistant stop       # Zatrzymaj usługę
voice-assistant status     # Status usługi
voice-assistant logs       # Pokaż logi
voice-assistant test-audio # Test audio
voice-assistant configure  # Konfiguracja
voice-assistant monitor    # Monitor wydajności
```

## ⚙️ Konfiguracja

### Plik konfiguracyjny

Lokalizacja: `/opt/ellmo/config.json`

```json
{
  "ollama_host": "localhost",
  "ollama_port": 11434,
  "model": "mistral",
  "language": "pl-PL",
  "wake_words": ["hey assistant", "asystent"],
  "tts_rate": 150,
  "tts_volume": 0.8,
  "audio_timeout": 5,
  "auto_start": true,
  "headless_mode": false
}
```

### Dostępne opcje

| Opcja | Opis | Domyślna wartość |
|-------|------|------------------|
| `ollama_host` | Adres serwera Ollama | `localhost` |
| `ollama_port` | Port Ollama | `11434` |
| `model` | Model AI do użycia | `mistral` |
| `language` | Język rozpoznawania mowy | `pl-PL` |
| `wake_words` | Słowa aktywujące | `["hey assistant", "asystent"]` |
| `tts_rate` | Prędkość mowy (50-300) | `150` |
| `tts_volume` | Głośność mowy (0.0-1.0) | `0.8` |
| `audio_timeout` | Timeout słuchania (sekundy) | `5` |
| `auto_start` | Autostart aplikacji | `true` |
| `headless_mode` | Tryb bezgłowy | `false` |

### Zmiana modelu AI

```bash
# Lista dostępnych modeli
ollama list

# Instalacja nowego modelu
ollama pull llama2

# Konfiguracja
voice-assistant configure
# Wybierz opcję 1 (Change AI model)
```

### Konfiguracja języka

Obsługiwane języki:
- `pl-PL` - Polski
- `en-US` - Angielski (USA)
- `en-GB` - Angielski (UK)
- `de-DE` - Niemiecki
- `fr-FR` - Francuski
- `es-ES` - Hiszpański
- `it-IT` - Włoski

## 🔊 Konfiguracja audio

### Test systemu audio

```bash
voice-assistant test-audio
```

### Rozwiązywanie problemów audio

**Brak uprawnień do mikrofonu**:
```bash
sudo usermod -a -G audio $USER
# Wyloguj się i zaloguj ponownie
```

**Problemy z PulseAudio**:
```bash
pulseaudio --kill
pulseaudio --start
```

**Raspberry Pi - włączenie audio**:
```bash
sudo raspi-config
# Advanced Options -> Audio -> Force 3.5mm jack
```

### Konfiguracja dla urządzeń embedded

**Raspberry Pi**:
- Włącz audio w `raspi-config`
- Sprawdź czy mikrofon USB jest rozpoznany: `arecord -l`
- Ustaw głośność: `alsamixer`

**Radxa/Rock Pi**:
- Sprawdź sterowniki audio: `lsmod | grep snd`
- Konfiguruj ALSA: `sudo alsactl init`

## 🖥️ Tryby pracy

### Tryb graficzny (domyślny)
- Pełny interfejs Flutter
- Wizualne wskaźniki statusu
- Historia rozmów

### Tryb headless
```bash
# Włączenie w konfiguracji
echo '{"headless_mode": true}' > /opt/ellmo/config.json

# Lub uruchomienie z parametrem
/opt/ellmo/start.sh --headless
```

### Tryb debug
```bash
/opt/ellmo/start.sh --debug
```

## 🔧 Rozwiązywanie problemów

### Częste problemy

**1. Ollama nie odpowiada**
```bash
sudo systemctl status ollama
sudo systemctl restart ollama
ollama list  # Sprawdź dostępne modele
```

**2. Brak rozpoznawania mowy**
```bash
# Test mikrofonu
arecord -d 5 test.wav
aplay test.wav

# Sprawdź uprawnienia
groups | grep audio
```

**3. Brak syntezy mowy**
```bash
# Test TTS
espeak-ng "test"
# lub
echo "test" | festival --tts
```

**4. Aplikacja nie startuje**
```bash
# Sprawdź logi
journalctl -u ellmo -f

# Test zależności
/opt/ellmo/start.sh --check
```

**5. Problemy z Flutter**
```bash
cd /opt/ellmo
flutter doctor
flutter clean
flutter pub get
flutter build linux --release
```

### Logi i diagnostyka

**Główne logi**:
```bash
journalctl -u ellmo -f
```

**Logi audio**:
```bash
tail -f /var/log/ellmo.log
```

**Logi Ollama**:
```bash
journalctl -u ollama -f
```

**Test całego systemu**:
```bash
voice-assistant info     # Informacje o systemie
voice-assistant monitor  # Monitor wydajności
```

## 📊 Monitoring wydajności

### Monitorowanie w czasie rzeczywistym
```bash
voice-assistant monitor
```

### Sprawdzenie zasobów
```bash
# Zużycie CPU/RAM przez aplikację
ps aux | grep ellmo

# Zużycie przez Ollama
ps aux | grep ollama

# Ogólne zużycie systemu
htop
```

### Optymalizacja wydajności

**Raspberry Pi**:
- Zwiększ `gpu_mem` w `/boot/config.txt`
- Użyj szybkiej karty SD (Class 10/U3)
- Zapewnij odpowiednie chłodzenie

**Systemy embedded**:
- Rozważ użycie mniejszych modeli AI
- Wyłącz niepotrzebne usługi systemowe
- Optymalizuj ustawienia Flutter

## 🔄 Aktualizacja

### Automatyczna aktualizacja
```bash
voice-assistant update
```

### Manualna aktualizacja
```bash
cd /opt/ellmo
git pull
flutter pub get
flutter build linux --release
sudo systemctl restart ellmo
```

## 🗑️ Deinstalacja

```bash
voice-assistant uninstall
```

Lub manualnie:
```bash
sudo systemctl stop ellmo
sudo systemctl disable ellmo
sudo rm /etc/systemd/system/ellmo.service
sudo rm -rf /opt/ellmo
sudo systemctl daemon-reload
```

## 🤝 Wkład w projekt

1. Fork repozytorium
2. Stwórz branch dla funkcji (`git checkout -b feature/AmazingFeature`)
3. Commit zmian (`git commit -m 'Add some AmazingFeature'`)
4. Push do brancha (`git push origin feature/AmazingFeature`)
5. Otwórz Pull Request

## 📝 Licencja

Projekt na licencji MIT. Zobacz plik `LICENSE` dla szczegółów.

## 🙏 Podziękowania

- [Flutter](https://flutter.dev/) - Framework UI
- [Ollama](https://ollama.ai/) - Lokalne modele AI
- [Mistral](https://mistral.ai/) - Model językowy
- [SpeechRecognition](https://pypi.org/project/SpeechRecognition/) - Rozpoznawanie mowy
- [pyttsx3](https://pypi.org/project/pyttsx3/) - Synteza mowy

## 📞 Wsparcie

- GitHub Issues: [Zgłoś problem](https://github.com/wronai/ellmo/issues)
- Wiki: [Dokumentacja](https://github.com/wronai/ellmo/wiki)
- Discussions: [Forum społeczności](https://github.com/wronai/ellmo/discussions)

---

**Stworzone z ❤️ dla społeczności open source**