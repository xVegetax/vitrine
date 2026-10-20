# Traduction française de Vitrine

`Core/SGLocalization.h` expose `SGLocalized`, réservé aux textes de présentation du mod. La première langue préférée d’iOS est lue une fois par lancement : `fr`, `fr-FR`, `fr-CA`, etc. activent le français. Toute entrée inconnue et les autres langues conservent le texte d’origine. Aucun changement des réglages de langue de Spotify n’est effectué.

Le catalogue source est `tweak/Sources/Core/Localization/fr.json`. Le générateur produit un dictionnaire Objective-C compilé dans le tweak : aucun chargement de ressource, serveur ou bundle supplémentaire n’est nécessaire. Les indices de choix et les clés persistées restent ceux d’origine. Les noms techniques, marques et contenus provenant de Spotify ne sont pas traduits automatiquement.

    node scripts/generate-localization.cjs
    node scripts/generate-localization.cjs --check
    node scripts/check-localization.cjs

Les textes littéraux sont traduits aux points de présentation. SGModRow et SGModSection traduisent leurs libellés et notes ; les listes de choix et menus traduisent leurs titres affichés en gardant les valeurs utilisées par leurs gestionnaires.

Validation restante : compilation iOS avec Theos/Xcode puis contrôle sur un iPhone en français et en anglais. Le simulateur web ne valide pas le code Objective-C. Le catalogue n’est pas une garantie de couverture intégrale : les phrases dynamiques et les textes absents du catalogue restent en anglais.
