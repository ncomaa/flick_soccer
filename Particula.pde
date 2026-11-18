/*
 * ============================================================
 *  PESTAÑA: Particula.pde
 * ============================================================
 *  Clase Particula: un papelito de confeti con posición, velocidad y
 *  aceleración (todo con PVector). Gira, se desvanece y muere.
 *
 *  Clase SistemaParticulas: dueña del ArrayList de partículas.
 *    - explosionGol(): crea el confeti del festejo.
 *    - actualizar(): mueve todas y borra las que murieron.
 *    - dibujar(): las dibuja.
 *
 *  Es sólo un efecto visual: no afecta la física del juego.
 *  Cada compu (servidor y cliente) crea sus propias partículas.
 * ============================================================
 */

class Particula {
  PVector pos;
  PVector vel;
  PVector acel;
  float vida;               // frames que le quedan
  float vidaMax;
  float tam;
  float angulo;
  float velAngulo;
  color col;

  Particula(float x, float y, PVector velInicial, color colorParticula) {
    pos = new PVector(x, y);
    vel = new PVector(velInicial.x, velInicial.y);
    acel = new PVector(0, 0.18);        // gravedad suave
    col = colorParticula;
    vidaMax = random(60, 110);
    vida = vidaMax;
    tam = random(6, 12);
    angulo = random(TWO_PI);
    velAngulo = random(-0.3, 0.3);
  }

  void actualizar() {
    vel.add(acel);
    vel.mult(0.985);                    // resistencia del aire
    pos.add(vel);
    angulo = angulo + velAngulo;
    vida = vida - 1;
  }

  boolean estaViva() {
    return vida > 0;
  }

  void dibujar() {
    float alfa = 255 * vida / vidaMax;  // se desvanece al morir
    pushMatrix();
    translate(pos.x, pos.y);
    rotate(angulo);
    noStroke();
    fill(red(col), green(col), blue(col), alfa);
    rect(-tam / 2, -tam / 4, tam, tam / 2);
    popMatrix();
  }
}

class SistemaParticulas {
  ArrayList<Particula> lista;
  int maximo;

  SistemaParticulas() {
    lista = new ArrayList<Particula>();
    maximo = 600;                       // tope para que no se llene de partículas
  }

  void explosionGol(float x, float y, color colorEquipo) {
    for (int i = 0; i < 180; i++) {
      if (lista.size() >= maximo) {
        return;
      }
      float ang = random(TWO_PI);
      float rapidez = random(2, 12);
      PVector v = new PVector(cos(ang) * rapidez, sin(ang) * rapidez - 3);

      // confeti de tres colores: el del equipo, dorado y blanco
      color c;
      if (i % 3 == 0) {
        c = colorEquipo;
      } else if (i % 3 == 1) {
        c = color(255, 215, 0);
      } else {
        c = color(255);
      }
      lista.add(new Particula(x, y, v, c));
    }
  }

  // Se recorre de atrás hacia adelante para borrar sin errores
  void actualizar() {
    for (int i = lista.size() - 1; i >= 0; i--) {
      Particula p = lista.get(i);
      p.actualizar();
      if (!p.estaViva()) {
        lista.remove(i);
      }
    }
  }

  void dibujar() {
    for (int i = 0; i < lista.size(); i++) {
      lista.get(i).dibujar();
    }
  }

  void limpiar() {
    lista.clear();
  }
}
