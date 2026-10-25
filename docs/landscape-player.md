# Lecteur en paysage

Dans l’interface redessinée : Réglages Vitrine > Lecteur > Lecteur en paysage. Désactivé par défaut. Tourner l’iPhone avec le lecteur ouvert affiche le lecteur horizontal ; le redresser revient au portrait. Sans paroles ouvertes, la pochette et les commandes occupent l’écran. Lorsque les paroles sont ouvertes, le lecteur utilise la disposition horizontale existante avec les paroles.

Le réglage « Paroles en paysage » reste indépendant : il autorise ce mode lorsque les paroles sont ouvertes, même si « Lecteur en paysage » est désactivé. La fermeture du lecteur ferme aussi sa fenêtre horizontale. Les autres fenêtres de Spotify ne sont pas autorisées à pivoter par ce réglage.

Validation à faire sur iPhone après compilation :

- Les deux réglages désactivés : pas d’ouverture automatique en paysage.
- Lecteur en paysage activé, paroles fermées : pochette, titre et commandes en paysage gauche et droite.
- Paroles ouvertes : affichage des paroles, puis passage à un titre sans paroles.
- Retour au portrait ; fermeture manuelle du plein écran ; rotation depuis un lecteur ouvert alors que l’iPhone est déjà horizontal.
- Fermeture du lecteur et navigation dans Spotify : pas de réouverture de l’écran horizontal.
- Vérification des zones sûres, VoiceOver, tailles de texte et Réduire les animations.

La compilation ne remplace pas cette vérification sur appareil.

## Progression et commandes

La barre horizontale affiche le temps écoulé et le temps restant. Le glissement prévisualise la
position ; le déplacement est envoyé une seule fois au relâchement. Une annulation ou un changement
de titre pendant le glissement n’envoie pas de déplacement. Une durée ou une position inconnue
désactive le curseur. VoiceOver peut ajuster la position par pas de cinq secondes.

Le curseur garde une zone de toucher de 44 points. Les contrôles restent visibles pendant le
glissement et lorsque VoiceOver est actif. Ils suivent le masquage existant des paroles le reste
du temps ; les commandes précédent, lecture/pause, suivant et sortie restent présentes.

Un refus de rotation ou une demande qui ne produit aucune orientation paysage ferme la fenêtre
supplémentaire et restitue la fenêtre précédente. Une ancienne réponse de rotation ne doit pas
fermer une fenêtre plus récente. Le passage en arrière-plan ferme également le plein écran.

Validation sur Mac : lancer les scénarios `landscape` et `landscape-denied` de `harness/player`.
Les scénarios existants `scroll`, `immersive` et `motion` restent à exécuter en régression.
Sur iPhone, vérifier aussi les deux sens de rotation, le verrouillage de rotation, les retournements
rapides, les morceaux sans durée, Spotify Connect, un changement de piste pendant un glissement,
VoiceOver français/anglais, le retour d’arrière-plan et les deux interfaces.
