#!/usr/bin/perl
# -*- encoding: utf-8; indent-tabs-mode: nil -*-
#
#     Simuler la reconnaissance de caractères par le logiciel Alice-OCR
#     Simulate the character recognition by Alice-OCR software
#     Copyright (C) 2017 Jean Forget
#
#     Voir la licence dans la documentation incluse ci-dessous.
#     See the license in the embedded documentation below.
#

use v5.10;
use strict;
use warnings;
use Tk;
use feature "switch";

my $etape = $ARGV[0] // 1;

my $fichier;
my $texte;
given ($etape) {
    when (1) { $fichier = 'Hello.gif'; $texte = '' }
    when (2) { $fichier = 'He11o.gif'; $texte = "He11o Wor1d I"; }
}


my $w = MainWindow->new();

if ($etape != 3) {
  $w->title("Alice OCR");
  my $image = $w->Photo(-file => $fichier);
  # Pourquoi utiliser un bouton pour afficher une photo ?
  # Parce que c'est plus simple et plus rapide qu'un Canvas
  $w->Button(-image => $image, -command => sub { exit })->pack(-side => 'left');
  # Ça, c'est vraiment un bouton. Sauf qu'il ne lance pas la reconnaissance, ce n'est qu'une simulation
  $w->Button(-text  => "Convert",  -command => sub { exit })->pack(-anchor => 'center', -side => 'left');
  my $wt = $w->Text(-height => 18, -width => 30, -font => 'Arial 24')->pack(-side => 'left');
  $wt->insert('end', $texte);
}
else {
  # La fenêtre annexe reliant un dessin à un caractère
  $w->title("Lier au caractère");
  my $dessus = $w->Frame()->pack(-side => 'top');
  $dessus->Label(-text => 'Car.')->pack(-side => 'left');
  $dessus->Entry()->pack(-side => 'left');
  my $dessous = $w->Frame()->pack(-side => 'top');
  $dessous->Button(-text => 'OK', -command => sub { exit })->pack(-side => 'left');
  $dessous->Button(-text => 'Annuler', -command => sub { exit })->pack(-side => 'left');
}

MainLoop;

__END__

=encoding utf8

=head1 NOM

demo.pl - maquettage du programme Alice-OCR

=head1 DESCRIPTION

Ce programme génère une fenêtre Perl-TK censée représenter le principe du logiciel
de reconnaissance de caractères Alice-OCR. Lancez l'application Perl-TK, puis
faites une copie d'écran.

=head1 UTILISATION

Simuler la situation avant la reconnaissance de caractères, le fichier graphique
étant chargé, mais le texte n'étant pas alimenté.

  perl demo.pl 1

Simuler la situation après la reconnaissance de caractères, avec des erreurs.

  perl demo.pl 2

Simuler la saisie du caractère associé à une zone du fichier graphiqueœ

  perl demo.pl 2 &
  perl demo.pl 3

Et s'arranger pour que les deux fenêtres se superposent comme il faut.

=head1 Fichiers

Le programme requiert deux fichiers dont le nom est imposé.

=over 4

=item * F<Hello.gif>

Le fichier pour l'étape 1 de la simulation. Le fichier graphique brut.

=item * F<He11o.gif>

Le fichier pour l'étape 2 de la simulation. Les caractères sont mis en évidence
avec des ovales de couleur.

=back

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

