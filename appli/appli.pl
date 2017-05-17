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
use MongoDB;
use YAML;
use GD;
use MIME::Base64;
use DateTime;
use experimental qw/switch/;

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
<br /><a href='/listedoc'>Liste des documents</a>
</body>
</html>
EOF

};


get '/listedoc' => sub {
  my $appli     = setting('username');
  my $mdp       = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $liste_ref = get_liste($appli, $mdp);
  return aff_liste($appli, $mdp,'', '', '', $liste_ref);
};

post '/credoc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc = body_parameters->get('document');
  my $fic = body_parameters->get('fichier');
  my $msg = credoc($appli, $mdp, $doc, $fic);
  if ($msg) {
    return aff_liste($appli, $mdp, $doc, $fic, $msg, get_liste($appli, $mdp));
  }
  #say "création du document $doc, basé sur le fichier $fic";

  redirect '/listedoc';
};

get '/doc/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_doc($appli, $mdp, $doc, 'base');
};

get '/grille/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_doc($appli, $mdp, $doc, 'grille');
};

post '/majgrille' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  my %param;
  unless ($appli) {
    redirect '/';
  }
  for my $par (qw/nom x0 y0 dx dy dirh cish dirv cisv/) {
    $param{$par} = body_parameters->get($par);
  }
  my $doc = $param{nom};
  #say YAML::Dump({ %param });
  my $msg = maj_grille($appli, $mdp, { %param });
  #say "Mise à jour de la grille pour $doc";
  redirect "/grille/$doc";
};

post '/valgrille' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc = body_parameters->get('nom');
  say "Validation de la grille pour $doc";
  redirect "/grille/$doc";
};

start;

sub get_liste {
  my ($appli, $mdp) = @_;
  my $client = MongoDB->connect('mongodb://localhost');
  my $coll   = $client->ns("$appli.Document");
  my $doc    = $coll->find;
  #say YAML::Dump($doc);
  my @liste;
  while(my $obj = $doc->next) {
   push @liste, $obj;
  }
  return [ @liste ];
}

sub get_doc {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost');
  my $coll   = $client->ns("$appli.Document");
  my $obj    = $coll->find_one({ nom => $doc });
  # say YAML::Dump($obj);
  return $obj;
}

sub credoc {
  my ($appli, $mdp, $doc, $fic) = @_;
  if ($doc !~ /^\w+$/) {
    return "Mauvais format pour le nom du document"
  }
  if ($fic !~ /^\w+\.png$/) {
    return "Mauvais format pour le nom du fichier";
  }
  my %obj = ( nom => $doc, fic => $fic, dx => 30, dy => 50, cish => 0, cisv => 0, etat => 1 );

  my $image = GD::Image->newFromPng($fic);
  my ($l, $h) = $image->getBounds();
  $obj{taille_x} = $l;
  $obj{taille_y} = $h;
  my @cpt = (0, 0);
  my @xmin = (1e99, 1e99);
  my @ymin = (1e99, 1e99);
  for my $x (0 .. $h - 1) {
    for my $y (0 .. $l - 1) {
      my $index  = $image->getPixel($x, $y);
      $cpt[$index]++;
      $xmin[$index] = $x if $xmin[$index] > $x;
      $ymin[$index] = $y if $ymin[$index] > $y;
    }
  }
  if ($cpt[0] < $cpt[1]) {
    $obj{ind_blanc} = 1;
    $obj{ind_noir}  = 0;
  }
  else {
    $obj{ind_blanc} = 0;
    $obj{ind_noir}  = 1;
  }
  $obj{nb_noirs} = $cpt[$obj{ind_noir}];
  $obj{x0}       = $xmin[$obj{ind_noir}];
  $obj{y0}       = $ymin[$obj{ind_noir}];
  $obj{dh_cre}   = horodatage();

  my $client = MongoDB->connect('mongodb://localhost');
  my $coll   = $client->ns("$appli.Document");
  my $res    = $coll->insert_one({ %obj });
  return '';
}

sub maj_grille {
  my ($appli, $mdp, $ref_param) = @_;
  my $doc      = $ref_param->{nom};

  my $info_doc = get_doc($appli, $mdp, $doc);
  #say YAML::Dump( $info_doc );

  my $fichier = $info_doc->{fic};
  my $image = GD::Image->newFromPng($fichier);
  $fichier =~ s/\.png$/-grille.png/;
  my $rouge = $image->colorAllocate(255,   0,   0);
  my $vert  = $image->colorAllocate(  0, 255,   0);
  my $bleu  = $image->colorAllocate(  0,   0, 255);

  my $noir = $info_doc->{ind_noir};
  my $x0 = $ref_param->{x0};
  my $y0 = $ref_param->{y0};
  my $dx = $ref_param->{dx};
  my $dy = $ref_param->{dy};
  my $coef_cx = $ref_param->{dx};
  my $coef_ly = $ref_param->{dy};
  my $coef_lx = 0;
  my $coef_cy = 0;
  if ($ref_param->{cish}) {
    if ($ref_param->{dirh} eq 'gauche') {
      $coef_lx = -1 / $ref_param->{cish};
    }
    else {
      $coef_lx = 1 / $ref_param->{cish};
    }
  }
  if ($ref_param->{cisv}) {
    if ($ref_param->{dirv} eq 'haut') {
      $coef_cy = -1 / $ref_param->{cisv};
    }
    else {
      $coef_cy = 1 / $ref_param->{cisv};
    }
  }
  #say "horizontal $ref_param->{cish}, vertical $ref_param->{cisv}";
  #say "coef lx = $coef_lx, ly = $coef_ly, cx = $coef_cx, cy = $coef_cy";

  my $l_max = int(($info_doc->{taille_y} - $y0) / $coef_ly);
  my $c_max = int(($info_doc->{taille_x} - $x0) / $coef_cx);
  for my $l (0..$l_max) {
    for my $c (0..$c_max) {
      my $x = int($x0 + $coef_cx * $c + $coef_lx * $l);
      my $y = int($y0 + $coef_cy * $c + $coef_ly * $l);
      my $couleur;
      if (($l + $c) % 2) {
        $couleur = $bleu;
      }
      else {
        $couleur = $vert;
      }
      for my $x1 (0,   $dx) {
        for my $y1 (0 .. $dy) {
          my $pixel = $image->getPixel($x +$x1, $y + $y1);
          if ($pixel == $noir) {
            $image->setPixel($x + $x1, $y + $y1, $rouge);
          }
          else {
            $image->setPixel($x + $x1, $y + $y1, $couleur);
          }
        }
      }
      for my $x1 (0 .. $dx) {
        for my $y1 (0,   $dy) {
          my $pixel = $image->getPixel($x +$x1, $y + $y1);
          if ($pixel == $noir) {
            $image->setPixel($x + $x1, $y + $y1, $rouge);
          }
          else {
            $image->setPixel($x + $x1, $y + $y1, $couleur);
          }
        }
      }
    }
  }
  open my $im, '>', $fichier
    or die "Ouverture $fichier $!";
  print $im $image->png;
  close $im
    or die "Fermeture $fichier $!";

  $ref_param->{dh_grille} = horodatage();
  $ref_param->{grille}    = $fichier;
  $ref_param->{etat}      = 2;
  my $client = MongoDB->connect('mongodb://localhost');
  my $coll   = $client->ns("$appli.Document");
  my $res    = $coll->update_many( { nom => $doc }, { '$set' => $ref_param } );

  return '';
}

sub aff_liste {
  my ($appli, $mdp, $doc, $fic, $msg, $liste_ref) = @_;

  # Élimination des caractères dangereux
  $doc =~ s/\W/?/g;
  $fic =~ s/[^.\w]/?/g;

  # Valeurs facultatives
  if ($doc ne '') {
    $doc = " value='$doc'";
  }
  if ($fic ne '') {
    $fic = " value='$fic'";
  }
  if ($msg ne '') {
    $msg = "<br />$msg";
  }

  my $liste = '';
  for (@{$liste_ref}) {
    my $elem .= "<a href='/doc/$_->{nom}'>$_->{nom}</a>";
    if ($_->{etat} >= 2) {
      $elem .= " <a href='/grille/$_->{nom}'>grille</a>";
    }
    $liste .= "<li>$elem</li>\n";
  }

  return <<"EOF"
<html>
<head>
<title>Liste des documents</title>
</head>
<body>
Appli&nbsp;: $appli
<br />
<a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>
<h1>Nouveau document</h1>
<form action='/credoc' method='post'>
Document&nbsp;: <input type='text' name='document' $doc />
Fichier&nbsp;: <input type='text' name='fichier' $fic />
<br /><input type='submit' value='ajouter' />
</form>
$msg
<hr />
<h1>Documents existants</h1>
<ul>
$liste
</ul>
</body>
</html>
EOF
}

sub aff_doc {
  my ($appli, $mdp, $doc, $variante) = @_;
  my $info = get_doc($appli, $mdp, $doc);

  # Libellé bidon car les états commencent en 1
  my @etat = ('bidon', 'Créé', 'Grille définie', 'Grille validée', 'Conversion effectuée', 'Fichier texte généré');

  # Mise en forme du cisaillement horizontal
  my $droite = '';
  my $gauche = '';
  given ($info->{dirh}) {
    when ('droite') { $droite = "checked='1'"; }
    when ('gauche') { $gauche = "checked='1'"; }
  }

  # Mise en forme du cisaillement vertical
  my $haut = '';
  my $bas  = '';
  given ($info->{dirv}) {
    when ('haut'  ) { $haut   = "checked='1'"; }
    when ('bas'   ) { $bas    = "checked='1'"; }
  }

  # Quel fichier graphique faut-il afficher ?
  my $fichier;
  given ($variante) {
    when ('base'  ) { $fichier = $info->{fic}   ; }
    when ('grille') { $fichier = $info->{grille}; }
  }
  my $image = GD::Image->newFromPng($fichier);
  my $data  = encode_base64($image->png);

  # Faut-il proposer la validation de la grille ?
  my $validation = '';
  if ($info->{etat} >= 2) {
    $validation = <<"EOF";
<h2>Validation de la grille</h2>
<form action='/valgrille' method='post'>
<input type='hidden' name='nom' value='$info->{nom}' />
<br /><input type='submit' value='Validation' />
</form>
EOF
  }
  my $association = '';
  if ($info->{etat} >= 3) {
    $association  = <<"EOF";
<h2>Association des Cellules avec des Glyphes</h2>
<form action='/association' method='post'>
<input type='hidden' name='nom' value='$info->{nom}' />
<br /><input type='submit' value='Lancer l association' />
</form>
EOF
  }
  my $generation = '';
  if ($info->{etat} >= 4) {
    $generation  = <<"EOF";
<h2>Generation du fichier texte</h2>
<form action='/generation' method='post'>
<input type='hidden' name='nom' value='$info->{nom}' />
<br /><input type='submit' value='Lancer la generation' />
</form>
EOF
  }
  

  return <<"EOF";
<html>
<head>
<title>Document $doc</title>
</head>
<body>
Appli&nbsp;: $appli
<br /><a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>

<h1>Document $doc</h1>
<p>$info->{taille_x} x $info->{taille_y} dont $info->{nb_noirs} pixels noirs.</p>
<p>$etat[ $info->{etat} ]</p>
<p>Création $info->{dh_cre} (UTC)</p>

<h2>Grille</h2>
<form action='/majgrille' method='post'>
<input type='hidden' name='nom' value='$info->{nom}' />
Origine&nbsp;: <input type='text' name='x0' value='$info->{x0}' /> <input type='text' name='y0' value='$info->{y0}' />
<br />Taille des cellules&nbsp;: largeur <input type='text' name='dx' value='$info->{dx}' /> hauteur <input type='text' name='dy' value='$info->{dy}' />
<br />Cisaillement horizontal&nbsp: 1 pixel vers la <input type='radio' name='dirh' value='gauche' $gauche >gauche
                                                    <input type='radio' name='dirh' value='droite' $droite >droite toutes les <input type='text' name='cish' value='$info->{cish}' /> lignes
<br />Cisaillement vertical&nbsp: 1 pixel vers le <input type='radio' name='dirv' value='haut' $haut >haut
                                                  <input type='radio' name='dirv' value='bas'  $bas  >bas tous les <input type='text' name='cisv' value='$info->{cisv}' /> caractères
<br /><input type='submit' value='grille' />
</form>
<p>Mise à jour de la grille $info->{dh_grille} (UTC)</p>
$validation
$association
$generation
<img src='data:image/png;base64,$data' alt='document $doc' />
</body>
</html>
EOF
};

sub horodatage {
  return DateTime->now->strftime("%Y-%m-%d %H:%M:%S");
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

