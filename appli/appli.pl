#!/usr/bin/perl
# -*- encoding: utf-8; indent-tabs-mode: nil -*-
#
#
#     Application interactive pour isoler et reconnaître les caractères dans une série de documents
#     Interactive app to isolate and recognise chars in a set of documents
#     Copyright (C) 2017 Jean Forget
#
#     Voir la licence dans la documentation incluse ci-dessous.
#     See the license in the embedded documentation below.
#

use v5.10;
use strict;
use warnings;
use Dancer2;

set 'session' => 'Simple';

get '/' => sub {
  return <<'EOF'
<html>
<head>
<title>Login</title>
</head>
<body>
<form action='/accueil' method='post'>
Appli&nbsp;: <input type='text' name='appli' />
<br />
Mot de passe&nbsp;: <input type='password' name='password' />
<br /><input type='submit' value='login' />
</form>
</body>
</html>
EOF
};

post '/accueil' => sub {
  my $appli = body_parameters->get('appli');
  my $mdp   = body_parameters->get('password');
  say "appli= $appli";
  set 'username' => $appli;
  set 'password' => $mdp;
  return <<"EOF";
<html>
<head>
<title>Accueil</title>
</head>
<body>
Appli&nbsp;: $appli
<br />
Mot de passe&nbsp;: $mdp
<br /><a href='/listedoc'>Liste des documents</a>
</body>
</html>
EOF

};


get '/listedoc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  my @liste = get_liste($appli, $mdp);
  my $liste = '';
  for (@liste) {
    $liste .= "<li><a href='/doc/$_'>$_</a></li>\n";
  }
  return <<"EOF"
<html>
<head>
<title>Liste des documents</title>
</head>
<body>
Appli&nbsp;: $appli
<br />
Mot de passe&nbsp;: $mdp
<br /><a href='/'>Retour</a>
<h1>Nouveau document</h1>
<form action='/credoc' method='post'>
Document&nbsp;: <input type='text' name='document' />
Fichier&nbsp;: <input type='text' name='fichier' />
<br /><input type='submit' value='ajouter' />
</form>
<hr />
<h1>Documents existants</h1>
<ul>
$liste
</ul>
</body>
</html>
EOF
};

post '/credoc' => sub {
  my $doc = body_parameters->get('document');
  my $fic = body_parameters->get('fichier');
  say "création du docuemnt $doc, basé sur le fichier $fic";
  redirect '/listedoc';
};

get '/doc/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  my $doc   = route_parameters->get('doc');
  return <<"EOF"
<html>
<head>
<title>Document $doc</title>
</head>
<body>
Appli&nbsp;: $appli
<br />
Mot de passe&nbsp;: $mdp
<br />Document $doc
<br /><a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>
</body>
</html>
EOF
};

start;

sub get_liste {
  return qw/doc1 doc2 doc3/;
}


__END__

=encoding utf8

=head1 NOM

appli.pl - application interactive pour isoler et reconnaître les caractères dans une série de documents

=head1 DESCRIPTION

Ce programme tourne sous C<Dancer2> et permet de traiter les différents documents
contenant des textes à extraire.

=head1 LANCEMENT

Se placer dans le répertoire contenant les fichiers graphiques. S<Puis :>

  perl ../appli/appli.pl

(ou similaire, si le chemin pour trouver F<appli.pl> est différent de l'exemple ci-dessus).

=head1 COPYRIGHT et LICENCE

Copyright 2017, Jean Forget

Ce programme est diffusé avec les mêmes conditions que Perl 5.16.3 :
la licence publique GPL version 1 ou ultérieure, ou bien la 
licence artistique Perl.

Vous pouvez trouver le texte en anglais de ces licences dans le
fichier <LICENSE> joint ou bien aux adresses
L<http://www.perlfoundation.org/artistic_license_1_0>
et L<http://www.gnu.org/licenses/gpl-1.0.html>.

Résumé en anglais de la GPL :

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 1, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., L<http://www.fsf.org/>.

