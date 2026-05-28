# Online IRT via Variational Inference — Design Contribution

**Date:** 2026-05-28
**Status:** Algorithmic specification (Phase 1 deliverable for proposal MT2(b)). Runtime implementation deferred to Phase 2 once a streaming infrastructure exists on the OLM platform.

---

## 1. Motivation & literature

Classical IRT calibration (mirt EM, B2 of this pipeline) is **offline**: every item parameter $b_j$ and every student EAP estimate $\hat\theta_{it}$ requires a batch over all responses. For a live OLM, ability needs to be updated *per response*, not per batch.

Three threads of prior work converge here:

- **Stochastic Variational Inference** (Hoffman, Blei, Wang & Paisley 2013) — replaces the full posterior with a parametric variational family $q(\theta_i)$ and optimises an Evidence Lower Bound (ELBO) via natural-gradient steps over mini-batches. Constant memory, sub-linear per-data-point cost.
- **Online IRT** (Cho, Yamaguchi & Suzuki 2021; "OIRT") — applies SVI to a 2PL IRT model, with held-fixed item parameters and a per-student Gaussian variational posterior. Demonstrated on millions of responses with single-pass updates.
- **Reparameterisation trick** (Kingma & Welling 2014) — enables low-variance Monte Carlo gradient estimates for the ELBO by writing $\theta_i = \mu_i + \sigma_i \cdot \varepsilon$ with $\varepsilon \sim \mathcal{N}(0,1)$.

For the 1PL case used in Phase 1, the model is conjugate enough that a closed-form Jaakkola–Jordan lower bound on the logistic likelihood is also available, which avoids Monte Carlo entirely.

---

## 2. Model

**Generative model.**

$$
\theta_i \sim \mathcal{N}(0, 1),\qquad
Y_{ij} \mid \theta_i, b_j \sim \mathrm{Bernoulli}\!\bigl(\sigma(\theta_i - b_j)\bigr),
$$

with item difficulties $\{b_j\}$ pre-calibrated and held fixed during online scoring.

**Variational family.** Mean-field per-student Gaussian:

$$
q_\phi(\theta_i) = \mathcal{N}(\theta_i \mid \mu_i,\ \sigma_i^2),\qquad
\phi_i = (\mu_i, \log \sigma_i^2).
$$

---

## 3. ELBO derivation

For one student $i$ with response history $\mathbf{Y}_i = (y_{i1}, \ldots, y_{iT_i})$ to items with difficulties $\mathbf{b}_i$,

$$
\log p(\mathbf{Y}_i) \;\geq\; \mathcal{L}(\phi_i) \;=\;
\mathbb{E}_{q}\bigl[\log p(\mathbf{Y}_i \mid \theta_i)\bigr]
\;+\; \mathbb{E}_{q}\bigl[\log p(\theta_i)\bigr]
\;-\; \mathbb{E}_{q}\bigl[\log q(\theta_i)\bigr].
$$

Each term:

**Prior expectation** (closed form, $\theta_i \sim \mathcal{N}(0,1)$):

$$
\mathbb{E}_q\bigl[\log p(\theta_i)\bigr]
= -\tfrac{1}{2}(\mu_i^2 + \sigma_i^2) - \tfrac{1}{2}\log(2\pi).
$$

**Entropy** (closed form, Gaussian $q$):

$$
-\mathbb{E}_q\bigl[\log q(\theta_i)\bigr] = \tfrac{1}{2}\log(2\pi e \sigma_i^2).
$$

**Likelihood expectation** — the only piece without a closed form. Two options:

- *Option A — Jaakkola–Jordan local variational bound on the logistic.* Introduce per-response auxiliary parameters $\xi_{it}$ and use

  $$
  \log \sigma(x) \;\geq\; \log \sigma(\xi) + \tfrac{1}{2}(x - \xi) - \lambda(\xi)(x^2 - \xi^2),\qquad
  \lambda(\xi) = \tfrac{\sigma(\xi) - 1/2}{2\xi}.
  $$

  Substituting $x = (2y_{it} - 1)(\theta_i - b_{it})$ and taking the Gaussian expectation yields a quadratic in $(\mu_i, \sigma_i^2)$ — closed-form optimum, alternating updates of $(\phi_i, \xi_i)$.

- *Option B — reparameterisation Monte Carlo.* Draw $\varepsilon^{(s)} \sim \mathcal{N}(0, 1)$, set $\theta_i^{(s)} = \mu_i + \sigma_i \varepsilon^{(s)}$, and

  $$
  \mathbb{E}_q\bigl[\log p(y_{it} \mid \theta_i)\bigr] \approx
  \frac{1}{S} \sum_{s=1}^{S}
  \Bigl[y_{it}\log \sigma\bigl(\theta_i^{(s)} - b_{it}\bigr)
  + (1 - y_{it})\log\bigl(1 - \sigma(\theta_i^{(s)} - b_{it})\bigr)\Bigr].
  $$

  With $S=1$ this is the standard amortised-VI estimator; gradients flow through the reparameterisation. Variance is well-controlled because the local likelihood is bounded.

Option A is preferred for production (no Monte Carlo noise, single-pass closed-form updates). Option B is preferred during prototyping for its flexibility (works for arbitrary IRT link functions, including 2PL and 3PL).

---

## 4. Streaming update pseudocode

```
Initialise μ_i ← 0, σ_i² ← 1     (diffuse prior)
For each incoming response (y_t, b_t) for student i, in arrival order:
    For k = 1 … K natural-gradient steps:
        Compute ∇φ ELBO (closed-form via Jaakkola, or via reparameterisation)
        φ_i ← φ_i + ρ_t · F⁻¹(φ_i) · ∇φ ELBO
    Emit (μ_i, σ_i²) as the current online (θ̂_i, SE_i²)
```

with step size $\rho_t = (t + \tau)^{-\kappa}$ for $\tau > 0,\ \kappa \in (0.5, 1]$ (Robbins–Monro). $F(\phi)$ is the Fisher information of the Gaussian variational family — known in closed form, so the natural gradient simplifies to a fixed-form preconditioned gradient.

For initialisation of a brand-new student, $(\mu_i, \sigma_i^2) = (0, 1)$ matches the EAP prior used in B3. Each subsequent response shrinks $\sigma_i^2$ monotonically (in expectation) and pulls $\mu_i$ toward the data — the same Bayesian-updating story Kalman tells, but with the logit observation handled natively rather than through a Gaussian approximation of the EAP.

---

## 5. Complexity

| Quantity | Per-student per-response cost | Memory |
|---|---|---|
| Natural-gradient step | $O(K)$ with $K$ small (3–5 sufficient) | $O(1)$ — store only $(\mu_i, \sigma_i^2)$ |
| Storage per student | $O(1)$ | $O(1)$ across the whole system |
| Parallelism | Embarrassingly parallel across students | — |

Compared to a full Kalman smoother run from scratch on $T$ occasions ($O(T)$ per student per refresh), the variational update is $O(1)$ per response and amortises trivially over a streaming workload.

---

## 6. Validation plan (Phase 2)

The runtime will be considered correct when:

1. **Offline agreement.** On a held-out OLM subset, single-pass VI estimates $(\mu_i^{\text{VI}}, \sigma_i^{\text{VI}})$ should agree with batch EAP $(\hat\theta_i^{\text{EAP}}, \mathrm{SE}_i^{\text{EAP}})$ within tolerance — e.g. $|\mu^{\text{VI}} - \hat\theta^{\text{EAP}}| < 0.1$ logit for $\geq 95\%$ of HS at $T = 10$.
2. **Sequential consistency.** The gap should shrink monotonically as $t \to T$.
3. **Kalman cross-check.** Replacing the logit likelihood with its Gaussian linearisation and feeding $(\hat\theta^{\text{EAP}}_{it}, \mathrm{SE}_{it})$ through the VI updater should reproduce the B6 Kalman smoother output exactly — VI generalises Kalman, so this is a sanity bound.

---

## 7. Connection to B6 Kalman (Phase 1)

The B6 Kalman smoother is precisely the **closed-form Gaussian special case** of this VI framework:

- Observation model: $\hat\theta_{it} = \theta_{it} + \varepsilon_{it}$ with $\varepsilon \sim \mathcal{N}(0, \mathrm{SE}_{it}^2)$ — Gaussian, so the local variational bound is exact and the natural-gradient step admits a closed form (the Kalman recursion).
- State model: $\theta_{it} = \theta_{i,t-1} + u_{it}$ with $u \sim \mathcal{N}(0, q_g)$ — linear Gaussian state-space.

VI generalises B6 in two ways: (1) it can be applied **directly to the Bernoulli responses** $y_{ij}$ without going through the EAP intermediate, removing the assumption that EAP gives a sufficient summary of the within-occasion likelihood; (2) it supports **non-Gaussian state dynamics** (e.g. heavy-tailed jumps to model exam shocks) and **non-linear observation models** (2PL, 3PL) within the same algorithmic skeleton.

Phase 1 delivers the Kalman special case as a working real-time estimator; Phase 2 will lift it to the full VI form.

---

## References

- Asparouhov, T., Hamaker, E. L., & Muthén, B. (2018). Dynamic structural equation models. *Structural Equation Modeling*, 25(3), 359–388.
- Cho, M., Yamaguchi, K., & Suzuki, T. (2021). Online learning of IRT models for proficiency tracking. *Educational Data Mining*.
- Driver, C. C., Oud, J. H. L., & Voelkle, M. C. (2017). Continuous-time structural equation modeling with R package ctsem. *Journal of Statistical Software*, 77(5).
- Hoffman, M. D., Blei, D. M., Wang, C., & Paisley, J. (2013). Stochastic variational inference. *JMLR*, 14, 1303–1347.
- Jaakkola, T. S., & Jordan, M. I. (2000). Bayesian parameter estimation via variational methods. *Statistics and Computing*, 10, 25–37.
- Kingma, D. P., & Welling, M. (2014). Auto-encoding variational Bayes. *ICLR*.
