# Kelanovela

Un gioco top-down 2D creato con Godot Engine.

## Struttura del progetto

- `scenes/`: Contiene le scene del gioco
  - `Main.tscn`: Scena principale con mappa e personaggio
  - `Player.tscn`: Scena del personaggio giocatore
  - `Map.tscn`: Scena della mappa importata
- `scripts/`: Contiene gli script GDScript
  - `Player.gd`: Script per il movimento del personaggio
  - `FollowCamera.gd`: Script per la telecamera che segue il personaggio
  - `InteractionManager.gd`: Script per gestire l'interazione con gli oggetti
- `map_export.tscn`: Mappa importata dal generatore esterno

## Comandi di gioco

- Movimento: frecce direzionali o WASD
- Interazione: Barra spaziatrice

## Caratteristiche

- Mappa dettagliata con collisioni
- Personaggio controllabile
- Telecamera che segue il personaggio
- Sistema di interazione con oggetti
addwawdd