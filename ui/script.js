function toggleDisplay(elem, disp) {
	if (elem.style.display == disp) {
		elem.style.display = 'none';
	} else {
		elem.style.display = disp;
	}
}

function toggleScoreboard() {
	toggleDisplay(document.querySelector('#scoreboard'), 'block');
}

function updateScoreboard(scores) {
	var scoreData = JSON.parse(scores);
	var scoreboard = document.querySelector('#player-scores');

	scoreboard.innerHTML = '';

	for (var i = 0; i < scoreData.length; ++i) {
		var div = document.createElement('div');
		div.className = 'player-score';

		var playerDiv = document.createElement('div');
		playerDiv.className = 'player';
		playerDiv.innerHTML = scoreData[i].name;

		var scoreDiv = document.createElement('div');
		scoreDiv.className = 'score';
		scoreDiv.innerHTML = scoreData[i].killed;

		div.appendChild(playerDiv);
		div.appendChild(scoreDiv);
		scoreboard.appendChild(div);
	}
}

function updateTotalUndeadKilled(total) {
	document.querySelector('#total-kills').innerHTML = total;
}

window.addEventListener('message', function(event) {
	switch (event.data.type) {
		case 'toggleScoreboard':
			toggleScoreboard();
			break;
		case 'updateScoreboard':
			updateScoreboard(event.data.scores);
			break;
		case 'updateTotalUndeadKilled':
			updateTotalUndeadKilled(event.data.total);
			break;
	}
});
