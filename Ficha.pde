/*
 * ============================================================
 *  PESTAÑA: Ficha.pde
 * ============================================================
 *  Clase Ficha: sirve para las fichas de los jugadores, para los
 *  arqueros y también para la pelota (cambia el tipo).
 *
 *  Responsabilidades:
 *    - Física con PVector: posición, velocidad y rozamiento.
 *    - Choque elástico disco-disco con otra ficha (según las masas).
 *    - Choque con los palos (círculos fijos) y rebote en las paredes.
 *    - Dibujo: la camiseta, el aro del equipo y el aro dorado del arquero.
 *
 *  Diferencia del arquero: radio 15% más grande (y por lo tanto más
 *  masa). Además, en FlickSoccer.pde su tiro sale con menos fuerza.
 * ============================================================
 */

class Ficha {
  int equipo;          // 1 o 2 (0 si es la pelota)
  int indice;          // 0 = arquero, 1 a 5 = jugadores de campo
  int tipo;            // TIPO_JUGADOR, TIPO_ARQUERO o TIPO_PELOTA

  PVector pos;         // posición
  PVector vel;         // velocidad (píxeles por frame)
  PVector inicio;      // posición de saque

  float radio;
  float masa;
  float friccion;      // se multiplica la velocidad por esto en cada frame

  Ficha(int equipoFicha, int indiceFicha, int tipoFicha) {
    equipo = equipoFicha;
    indice = indiceFicha;
    tipo = tipoFicha;

    pos = new PVector(0, 0);
    vel = new PVector(0, 0);
    inicio = new PVector(0, 0);

    float centroY = campoY + campoAlto / 2.0;

    if (tipo == TIPO_PELOTA) {
      radio = 12;
      masa = 0.35;
      friccion = 0.98;
      inicio.set(campoX + campoAncho / 2.0, centroY);
    } else {
      radio = 22;
      masa = 1.0;
      friccion = 0.972;
      if (tipo == TIPO_ARQUERO) {
        radio = 22 * 1.15;                  // 15% más grande
        masa = 1.15 * 1.15;                 // la masa crece con el área
      }
      // formación: distancia desde el arco propio y desplazamiento vertical
      float[] dx = { 40, 170, 170, 310, 310, 340 };
      float[] dy = { 0, -110, 110, -170, 170, 0 };
      float x = campoX + dx[indice];
      if (equipo == 2) {
        x = campoX + campoAncho - dx[indice];
      }
      inicio.set(x, centroY + dy[indice]);
    }
    reiniciar();
  }

  void reiniciar() {
    pos.set(inicio);
    vel.set(0, 0);
  }

  // ============================================================
  //  FÍSICA
  // ============================================================
  void mover() {
    pos.add(vel);
    vel.mult(friccion);
    if (vel.mag() < UMBRAL_QUIETO) {
      vel.set(0, 0);
    }
  }

  // Choque elástico entre dos discos (this y otra).
  //  1. Si se superponen, se los separa (más la que pesa menos).
  //  2. Si se están acercando, se aplica un impulso a lo largo de la
  //     línea que une los centros (la normal del choque).
  // Devuelve true si hubo choque (así FlickSoccer.pde sabe quién tocó la pelota).
  boolean chocarCon(Ficha otra) {
    PVector delta = PVector.sub(otra.pos, pos);
    float d = delta.mag();
    float minD = radio + otra.radio;
    if (d >= minD) {
      return false;
    }
    if (d < 0.0001) {
      delta.set(1, 0);
      d = 1;
    }
    PVector n = PVector.div(delta, d);          // normal unitaria (de this hacia otra)

    float invA = 1.0 / masa;
    float invB = 1.0 / otra.masa;
    float suma = invA + invB;

    float solapamiento = minD - d;
    pos.sub(PVector.mult(n, solapamiento * invA / suma));
    otra.pos.add(PVector.mult(n, solapamiento * invB / suma));

    PVector velRelativa = PVector.sub(vel, otra.vel);
    float vn = velRelativa.dot(n);              // cuánto se acercan
    if (vn <= 0) {
      return true;                              // ya se están alejando
    }
    float impulso = (1 + REBOTE_CHOQUE) * vn / suma;
    vel.sub(PVector.mult(n, impulso * invA));
    otra.vel.add(PVector.mult(n, impulso * invB));
    return true;
  }

  // Choque contra un palo del arco (un círculo que no se mueve)
  void chocarConPoste(PVector poste, float rPoste) {
    PVector delta = PVector.sub(pos, poste);
    float d = delta.mag();
    float minD = radio + rPoste;
    if (d >= minD || d < 0.0001) {
      return;
    }
    PVector n = PVector.div(delta, d);
    pos.set(PVector.add(poste, PVector.mult(n, minD)));
    float vn = vel.dot(n);
    if (vn < 0) {
      vel.sub(PVector.mult(n, (1 + REBOTE_PARED) * vn));
    }
  }

  // Rebote contra los bordes de la cancha.
  // Las fichas nunca entran a los arcos; la pelota sí puede entrar por la boca.
  void rebotarParedes() {
    float izq = campoX + radio;
    float der = campoX + campoAncho - radio;
    float arr = campoY + radio;
    float aba = campoY + campoAlto - radio;

    if (tipo == TIPO_PELOTA) {
      boolean enBoca = (pos.y > golY1 && pos.y < golY2);
      if (enBoca) {
        izq = campoX - golProf + radio;         // el fondo de la red
        der = campoX + campoAncho + golProf - radio;
      }
      if (pos.x < campoX || pos.x > campoX + campoAncho) {
        arr = golY1 + radio;                    // adentro del arco: el techo y el piso de la red
        aba = golY2 - radio;
      }
    }

    if (pos.x < izq) {
      pos.x = izq;
      vel.x = abs(vel.x) * REBOTE_PARED;
    }
    if (pos.x > der) {
      pos.x = der;
      vel.x = -abs(vel.x) * REBOTE_PARED;
    }
    if (pos.y < arr) {
      pos.y = arr;
      vel.y = abs(vel.y) * REBOTE_PARED;
    }
    if (pos.y > aba) {
      pos.y = aba;
      vel.y = -abs(vel.y) * REBOTE_PARED;
    }
  }

  // ============================================================
  //  DIBUJO
  // ============================================================
  void dibujar(boolean resaltada) {
    if (tipo == TIPO_PELOTA) {
      dibujarPelota();
      return;
    }
    float d = radio * 2;

    // sombra
    noStroke();
    fill(0, 60);
    ellipse(pos.x + 3, pos.y + 4, d, d);

    // halo parpadeante: esta ficha se puede tirar
    if (resaltada) {
      noFill();
      stroke(255, 255, 255, 140 + 100 * sin(frameCount * 0.15));
      strokeWeight(5);
      ellipse(pos.x, pos.y, d + 14, d + 14);
    }

    // camiseta y aro del color del equipo
    image(imgCamisetas[camisetaDe(equipo)], pos.x, pos.y, d, d);
    noFill();
    stroke(colorEquipo(equipo));
    strokeWeight(4);
    ellipse(pos.x, pos.y, d, d);

    // el arquero tiene un segundo aro dorado
    if (tipo == TIPO_ARQUERO) {
      stroke(255, 215, 0);
      strokeWeight(3);
      ellipse(pos.x, pos.y, d - 12, d - 12);
    }
  }

  void dibujarPelota() {
    float d = radio * 2;
    noStroke();
    fill(0, 70);
    ellipse(pos.x + 2, pos.y + 3, d, d);

    stroke(20);
    strokeWeight(2);
    fill(255);
    ellipse(pos.x, pos.y, d, d);

    // pentágono negro que gira según por dónde está en la cancha
    pushMatrix();
    translate(pos.x, pos.y);
    rotate((pos.x + pos.y) / radio * 0.5);
    noStroke();
    fill(25);
    beginShape();
    for (int i = 0; i < 5; i++) {
      float a = -HALF_PI + i * TWO_PI / 5;
      vertex(cos(a) * radio * 0.5, sin(a) * radio * 0.5);
    }
    endShape(CLOSE);
    popMatrix();
  }
}
