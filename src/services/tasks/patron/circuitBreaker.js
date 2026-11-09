"use strict";

const STATES = Object.freeze({
  CLOSED: "CLOSED",
  OPEN: "OPEN",
  HALF_OPEN: "HALF_OPEN",
});

function positiveInt(value, fallback) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : fallback;
}

function openCircuitError(name) {
  const err = new Error(`Circuito abierto para ${name}`);
  err.code = "EOPENBREAKER";
  return err;
}

function timeoutError(timeoutMs) {
  const err = new Error(`Tiempo de espera agotado después de ${timeoutMs} ms`);
  err.code = "ETIMEDOUT";
  return err;
}

/**
 * Implementación mínima del patrón Circuit Breaker.
 *
 * Estados:
 *  - CLOSED: las llamadas pasan y se registran sus resultados.
 *  - OPEN: las llamadas se rechazan inmediatamente hasta que venza resetTimeoutMs.
 *  - HALF_OPEN: se permite una llamada de prueba para decidir si se cierra.
 */
class CircuitBreaker {
  constructor(fn, options = {}) {
    if (typeof fn !== "function") {
      throw new TypeError("CircuitBreaker requiere una función");
    }

    this.fn = fn;
    this.name = options.name || "dependencia";
    this.timeoutMs = positiveInt(options.timeoutMs, 2500);
    this.volumeThreshold = positiveInt(options.volumeThreshold, 5);
    this.errorThresholdPercentage = positiveInt(
      options.errorThresholdPercentage,
      50,
    );
    this.resetTimeoutMs = positiveInt(options.resetTimeoutMs, 10000);
    this.rollingCountTimeoutMs = positiveInt(
      options.rollingCountTimeoutMs,
      10000,
    );
    this.onStateChange =
      typeof options.onStateChange === "function"
        ? options.onStateChange
        : () => {};

    this.state = STATES.CLOSED;
    this.openedAt = null;
    this.halfOpenInFlight = false;
    this.window = [];

    this.stats = {
      fires: 0,
      successes: 0,
      failures: 0,
      rejects: 0,
      timeouts: 0,
      stateChanges: 0,
    };
  }

  getState() {
    return this.state;
  }

  getStats() {
    const now = Date.now();
    this.pruneWindow(now);
    const failures = this.window.filter((entry) => !entry.ok).length;
    const failureRate =
      this.window.length === 0
        ? 0
        : Math.round((failures / this.window.length) * 100);

    return {
      name: this.name,
      state: this.state,
      openedAt: this.openedAt,
      windowCalls: this.window.length,
      failureRate,
      ...this.stats,
    };
  }

  async fire(...args) {
    this.stats.fires += 1;
    const now = Date.now();

    if (this.state === STATES.OPEN) {
      if (now - this.openedAt < this.resetTimeoutMs) {
        this.stats.rejects += 1;
        throw openCircuitError(this.name);
      }
      this.transition(STATES.HALF_OPEN, "venció resetTimeoutMs");
    }

    if (this.state === STATES.HALF_OPEN && this.halfOpenInFlight) {
      this.stats.rejects += 1;
      throw openCircuitError(this.name);
    }

    const isProbe = this.state === STATES.HALF_OPEN;
    if (isProbe) {
      this.halfOpenInFlight = true;
    }

    try {
      const result = await this.withTimeout(
        Promise.resolve().then(() => this.fn(...args)),
      );
      this.onSuccess();
      return result;
    } catch (err) {
      this.onFailure(err);
      throw err;
    } finally {
      if (isProbe) {
        this.halfOpenInFlight = false;
      }
    }
  }

  onSuccess() {
    this.stats.successes += 1;

    if (this.state === STATES.HALF_OPEN) {
      this.transition(STATES.CLOSED, "la llamada de prueba fue exitosa");
      return;
    }

    if (this.state === STATES.CLOSED) {
      this.record(true);
    }
  }

  onFailure(err) {
    this.stats.failures += 1;
    if (err && err.code === "ETIMEDOUT") {
      this.stats.timeouts += 1;
    }

    if (this.state === STATES.HALF_OPEN) {
      this.transition(STATES.OPEN, "la llamada de prueba falló");
      return;
    }

    if (this.state === STATES.CLOSED) {
      this.record(false);
    }
  }

  record(ok) {
    this.window.push({ ok, at: Date.now() });
    this.pruneWindow(Date.now());

    if (this.window.length < this.volumeThreshold) {
      return;
    }

    const failures = this.window.filter((entry) => !entry.ok).length;
    const failureRate = (failures / this.window.length) * 100;

    if (failureRate >= this.errorThresholdPercentage) {
      this.transition(
        STATES.OPEN,
        `${Math.round(failureRate)}% de fallas en ${this.window.length} llamadas`,
      );
    }
  }

  pruneWindow(now) {
    const from = now - this.rollingCountTimeoutMs;
    this.window = this.window.filter((entry) => entry.at >= from);
  }

  transition(nextState, reason) {
    if (this.state === nextState) {
      return;
    }

    const previousState = this.state;
    this.state = nextState;
    this.stats.stateChanges += 1;

    if (nextState === STATES.OPEN) {
      this.openedAt = Date.now();
      this.window = [];
    } else if (nextState === STATES.CLOSED) {
      this.openedAt = null;
      this.halfOpenInFlight = false;
      this.window = [];
    } else if (nextState === STATES.HALF_OPEN) {
      this.halfOpenInFlight = false;
    }

    try {
      this.onStateChange({
        name: this.name,
        from: previousState,
        to: nextState,
        reason,
        at: new Date().toISOString(),
      });
    } catch (err) {
      console.error(`[circuit:${this.name}] error en onStateChange: ${err.message}`);
    }
  }

  withTimeout(promise) {
    let timer;
    const timeout = new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(timeoutError(this.timeoutMs)), this.timeoutMs);
    });

    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }
}

module.exports = { CircuitBreaker, STATES };
