#' Select variables.
#'
#' These functions power [select()] and [rename()].
#'
#' @param vars A character vector of existing column names.
#' @param ...,args Expressions to compute
#'
#'   These arguments are automatically [quoted][rlang::quo] and
#'   [evaluated][rlang::eval_tidy] in a context where elements of
#'   `vars` are objects representing their positions within
#'   `vars`. They support [unquoting][rlang::quasiquotation] and
#'   splicing. See `vignette("programming")` for an introduction to
#'   these concepts.
#' @param include,exclude Character vector of column names to always
#'   include/exclude.
#' @export
#' @keywords internal
#' @return A named character vector. Values are existing column names,
#'   names are new names.
#' @examples
#' # Keep variables
#' select_vars(names(iris), everything())
#' select_vars(names(iris), starts_with("Petal"))
#' select_vars(names(iris), ends_with("Width"))
#' select_vars(names(iris), contains("etal"))
#' select_vars(names(iris), matches(".t."))
#' select_vars(names(iris), Petal.Length, Petal.Width)
#' select_vars(names(iris), one_of("Petal.Length", "Petal.Width"))
#'
#' df <- as.data.frame(matrix(runif(100), nrow = 10))
#' df <- df[c(3, 4, 7, 1, 9, 8, 5, 2, 6, 10)]
#' select_vars(names(df), num_range("V", 4:6))
#'
#' # Drop variables
#' select_vars(names(iris), -starts_with("Petal"))
#' select_vars(names(iris), -ends_with("Width"))
#' select_vars(names(iris), -contains("etal"))
#' select_vars(names(iris), -matches(".t."))
#' select_vars(names(iris), -Petal.Length, -Petal.Width)
#'
#' # Rename variables
#' select_vars(names(iris), petal_length = Petal.Length)
#' select_vars(names(iris), petal = starts_with("Petal"))
#'
#' # Rename variables preserving all existing
#' rename_vars(names(iris), petal_length = Petal.Length)
#'
#' # You can unquote names or formulas (or lists of)
#' select_vars(names(iris), !!! list(~Petal.Length))
#' select_vars(names(iris), !! quote(Petal.Length))
select_vars <- function(vars, ..., include = character(), exclude = character()) {
  args <- quos(...)

  if (is_empty(args)) {
    vars <- setdiff(include, exclude)
    return(set_names(vars, vars))
  }

  # Set current_vars so available to select_helpers
  old <- set_current_vars(vars)
  on.exit(set_current_vars(old), add = TRUE)

  # Map variable names to their positions: this keeps integer semantics
  names_list <- set_names(as.list(seq_along(vars)), vars)

  # if the first selector is exclusive (negative), start with all columns
  initial_case <- if (is_negated(args[[1]])) list(seq_along(vars)) else integer(0)

  # Evaluate symbols in an environment where columns are bound, but
  # not calls (select helpers are scoped in the calling environment)
  is_helper <- map_lgl(args, function(x) is_lang(x) && !is_lang(x, c("-", ":")))
  ind_list <- map_if(args, is_helper, eval_tidy)
  ind_list <- map_if(ind_list, !is_helper, eval_tidy, names_list)

  ind_list <- c(initial_case, ind_list)
  names(ind_list) <- c(names2(initial_case), names2(args))

  is_numeric <- map_lgl(ind_list, is.numeric)
  if (any(!is_numeric)) {
    bad <- args[!is_numeric]

    bad_calls(bad, "must resolve to integer column positions, ",
      "not {type_of(first_bad)}",
      first_bad = ind_list[!is_numeric][[1]]
    )
  }

  incl <- combine_vars(vars, ind_list)

  # Include/exclude specified variables
  sel <- set_names(vars[incl], names(incl))
  sel <- c(setdiff2(include, sel), sel)
  sel <- setdiff2(sel, exclude)

  # Ensure all output vars named
  if (is_empty(sel)) {
    names(sel) <- sel
  } else {
    unnamed <- names2(sel) == ""
    names(sel)[unnamed] <- sel[unnamed]
  }

  sel
}

#' @rdname se-deprecated
#' @inheritParams select_vars
#' @export
select_vars_ <- function(vars, args, include = character(), exclude = character()) {
  args <- compat_lazy_dots(args, caller_env())
  select_vars(vars, !!! args, include = include, exclude = exclude)
}

setdiff2 <- function(x, y) {
  x[match(x, y, 0L) == 0L]
}

#' @export
#' @rdname select_vars
#' @param strict If `TRUE`, will throw an error if you attempt to rename a
#'   variable that doesn't exist.
rename_vars <- function(vars, ..., strict = TRUE) {
  args <- quos(...)
  if (any(names2(args) == "")) {
    abort("All arguments must be named")
  }

  is_name <- map_lgl(args, is_symbol)
  if (!all(is_name)) {
    bad <- args[!is_name]
    bad_named_calls(bad, "must be unquoted variable names, ",
      "not {type_of(first_bad_rhs)}",
      first_bad_rhs = f_rhs(bad[[1]])
    )
  }

  old_vars <- map_chr(args, as_name)
  new_vars <- names(args)

  unknown_vars <- setdiff(old_vars, vars)
  if (strict && length(unknown_vars) > 0) {
    bad_args(unknown_vars, "unknown variables")
  }

  select <- set_names(vars, vars)
  names(select)[match(old_vars, vars)] <- new_vars

  select
}

#' @export
#' @rdname se-deprecated
rename_vars_ <- function(vars, args) {
  args <- compat_lazy_dots(args, caller_env())
  rename_vars(vars, !!! args)
}
