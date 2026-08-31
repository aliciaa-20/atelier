tell application "Spotify"
	set playerState to player state as text
	set playerPos to player position
	if playerState is "stopped" then
		return playerState & " | nothing loaded"
	end if
	set theTrack to current track
	return playerState & ¬
		" || name=" & (name of theTrack) & ¬
		" || artist=" & (artist of theTrack) & ¬
		" || album=" & (album of theTrack) & ¬
		" || duration=" & (duration of theTrack) & ¬
		" || position=" & playerPos & ¬
		" || artworkURL=" & (artwork url of theTrack)
end tell
