# ==============================================================================
# bifactor_scorer.R -- helper, sourced by the two vsi_goal_relative validation scripts
#
# The exact bifactor scorer, factored out so the bootstrap and the held-out
# test use the SAME code path as build_irt_vsi_goal_relative.R. Given the general
# factor, each series depends on one goal factor only, so no integral exceeds
# two dimensions. plogis(., log.p=TRUE) is required: -log1p(exp(-z)) overflows
# at |z| ~ 770 and turns every country-year into NaN.
#
# PROVENANCE  Recovered 14 Nov 2026 from the session that ran it (10 Nov 2026, as used by the vsi_goal_relative bootstrap attempt 3 and held-out runs).
# The logic is exactly as run. Changed for the repo: nothing but this header.
# ==============================================================================
score_bifactor <- function(fit, X = NULL, K = 61L, LIM = 6) {
  cf   <- coef(fit, simplify = TRUE)$items
  spec <- fit@Internals$bfactor$specific
  # as.matrix on BOTH branches: irt_prep hands out `resp` as a data.frame, and a
  # data.frame in %*% gives "requires numeric/complex matrix/vector arguments"
  X <- if (is.null(X)) as.matrix(fit@Data$data) else as.matrix(X)
  X <- X[, rownames(cf), drop = FALSE]
  N <- nrow(X); J <- ncol(X); G <- max(spec)

  aG <- cf[, "a1"]
  aS <- vapply(seq_len(J), function(j) cf[j, paste0("a", spec[j] + 1L)], numeric(1))
  dd <- cf[, "d"]

  tt <- seq(-LIM, LIM, length.out = K)
  lw <- dnorm(tt, log = TRUE); lw <- lw - log(sum(exp(lw)))
  lse <- function(M) { mx <- apply(M, 1, max); mx[!is.finite(mx)] <- 0
                       mx + log(rowSums(exp(M - mx))) }

  goal_LL <- function(g) {
    idx <- which(spec == g); Xg <- X[, idx, drop = FALSE]
    A <- array(0, c(N, K, K))
    for (k in seq_len(K)) {
      lp <- matrix(0, N, K)
      for (m in seq_len(K)) {
        z <- aG[idx] * tt[k] + aS[idx] * tt[m] + dd[idx]
        lp[, m] <- Xg %*% plogis(z, log.p = TRUE) +
                   (1 - Xg) %*% plogis(-z, log.p = TRUE)
      }
      A[, k, ] <- lp
    }
    A
  }
  pm <- function(logp, nodes) {
    logp <- logp - apply(logp, 1, max)
    w <- exp(logp); w <- w / rowSums(w)
    m <- as.numeric(w %*% nodes)
    list(ev = m, sd = sqrt(pmax(as.numeric(w %*% (nodes^2)) - m^2, 0)))
  }

  logLg <- array(0, c(N, K, G))
  for (g in seq_len(G)) {
    A <- goal_LL(g)
    for (k in seq_len(K)) logLg[, k, g] <- lse(sweep(A[, k, ], 2, lw, "+"))
  }
  S <- apply(logLg, c(1, 2), sum)
  if (any(!is.finite(S))) return(NULL)

  out <- matrix(NA_real_, N, G); ses <- matrix(NA_real_, N, G)
  for (g in seq_len(G)) {
    A <- goal_LL(g); off <- S - logLg[, , g]
    jm <- matrix(-Inf, N, K)
    for (k in seq_len(K)) {
      term <- sweep(A[, k, ], 2, lw, "+") + lw[k] + off[, k]
      mx <- pmax(jm, term); jm <- mx + log(exp(jm - mx) + exp(term - mx))
    }
    mg <- pm(jm, tt); out[, g] <- mg$ev; ses[, g] <- mg$sd
  }
  list(score = out, se = ses, general = pm(sweep(S, 2, lw, "+"), tt))
}

# Warm start a reduced or resampled model from the full-data estimates, BY NAME.
# Slicing the full values table instead produces a spec mirt rejects with
# "itemtype specification is not the correct length".
warm_pars <- function(M, sp, start, prior_sd = 2) {
  v <- as.data.frame(bfactor(M, sp, pars = "values"))
  m <- match(paste(v$item, v$name), paste(start$item, start$name))
  v$value[!is.na(m)] <- start$value[m[!is.na(m)]]
  i <- grepl("^a[0-9]+$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- prior_sd
  v
}
