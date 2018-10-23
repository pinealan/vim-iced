let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#iced#new()
let s:D = s:V.import('Data.Dict')
let s:L = s:V.import('Data.List')

let s:default_ns_favorites = {
      \ 'clj': {
      \   'clojure.edn': 'edn',
      \   'clojure.java.io': 'io',
      \   'clojure.set': 'set',
      \   'clojure.spec.alpha': 's',
      \   'clojure.spec.gen.alpha': 'sgen',
      \   'clojure.spec.test.alpha': 'stest',
      \   'clojure.string': 'str',
      \   'clojure.walk': 'walk',
      \   'clojure.zip': 'zip',
      \   },
      \ 'cljs': {
      \   'cljs.reader': 'reader',
      \   'cljs.spec.alpha': 's',
      \   'cljs.spec.gen.alpha': 'sgen',
      \   'cljs.spec.test.alpha': 'stest',
      \   'clojure.set': 'set',
      \   'clojure.string': 'str',
      \   'clojure.walk': 'walk',
      \   'clojure.zip': 'zip',
      \   },
      \ }
let g:iced#ns#favorites
      \ = get(g:, 'iced#ns#favorites', s:default_ns_favorites)

""" iced#nrepl#ns#refactor#clean
""" ----------------------------------------------------------------

function! s:clean_ns(resp) abort
  if has_key(a:resp, 'error')
    return iced#nrepl#eval#err(a:resp['error'])
  endif
  if has_key(a:resp, 'ns')
    if empty(a:resp['ns'])
      return iced#message#info('already_clean')
    endif

    call iced#nrepl#ns#util#replace(a:resp['ns'])
    call iced#message#info('cleaned')
  endif
endfunction

function! iced#nrepl#ns#refactor#clean() abort
  call iced#nrepl#op#refactor#clean_ns(funcref('s:clean_ns'))
endfunction

""" iced#nrepl#ns#refactor#add_missing
""" ----------------------------------------------------------------

function! s:parse_candidates(candidates) abort
  let res = []
  for candidate in split(substitute(a:candidates, '[(),{]', '', 'g'), '} \?')
    let x = s:D.from_list(split(candidate, ' \+'))
    call add(res, x)
  endfor
  " ex. [{':type': ':ns', ':name': 'clojure.set'}, {':type': ':ns', ':name': 'clojure.string'}]
  return res
endfunction

function! s:symbol_to_alias(symbol) abort
  let arr = split(a:symbol, '/')
  if len(arr) == 2 || stridx(a:symbol, '/') != -1
    return arr[0]
  endif
  return ''
endfunction

function! s:add_ns(ns_name, symbol_alias) abort
  call iced#nrepl#ns#util#add(a:ns_name, a:symbol_alias)
  call iced#message#info_str(printf(iced#message#get('ns_added'), a:ns_name))
endfunction

function! s:add_all_ns_alias_candidates(candidates, symbol_alias) abort
  if empty(a:symbol_alias) | return a:candidates | endif

  let alias_dict = iced#nrepl#op#refactor#sync#all_ns_aliases()
  let k = iced#nrepl#current_session_key()
  if !has_key(alias_dict, k)
    return []
  endif

  let aliases = alias_dict[k]
  let names = []
  for k in filter(keys(aliases), {_, v -> stridx(v, a:symbol_alias) == 0})
    let names = names + aliases[k]
  endfor
  let names = filter(names, {_, v -> !s:L.has(a:candidates, v)})
  return a:candidates + names
endfunction

function! s:resolve_missing(symbol, resp) abort
  if !has_key(a:resp, 'candidates') | return | endif
  let symbol_alias = s:symbol_to_alias(a:symbol)

  if empty(a:resp['candidates'])
    let ns_candidates = []
  else
    let alias_dict = iced#nrepl#ns#alias#dict(iced#nrepl#ns#get())
    if has_key(alias_dict, symbol_alias)
      return iced#message#error_str(printf(iced#message#get('alias_exists'), symbol_alias))
    endif

    let existing_ns = values(alias_dict) + ['clojure.core']
    let candidates = s:parse_candidates(a:resp['candidates'])
    let ns_candidates = filter(candidates, {_, v -> v[':type'] ==# ':ns'})
    let ns_candidates = filter(ns_candidates, {_, v -> !s:L.has(existing_ns, v[':name'])})
    let ns_candidates = map(ns_candidates, {_, v -> v[':name']})
  endif

  let ns_candidates = s:add_all_ns_alias_candidates(ns_candidates, symbol_alias)

  let c = len(ns_candidates)
  if c == 1
    call s:add_ns(ns_candidates[0], symbol_alias)
  elseif c > 1
    call iced#selector({
        \ 'candidates': ns_candidates,
        \ 'accept': {_, ns_name -> s:add_ns(ns_name, symbol_alias)}
        \ })
  else
    return iced#message#echom('no_candidates')
  endif
endfunction

function! iced#nrepl#ns#refactor#add_missing(symbol) abort
  let symbol = empty(a:symbol) ? expand('<cword>') : a:symbol
  call iced#nrepl#op#refactor#add_missing(symbol, {resp -> s:resolve_missing(symbol, resp)})
endfunction

""" iced#nrepl#ns#refactor#add
""" ----------------------------------------------------------------

function! s:add(ns_name) abort
  let favorites = get(g:iced#ns#favorites, iced#nrepl#current_session_key(), {})
  if has_key(favorites, a:ns_name)
    let ns_alias = favorites[a:ns_name]
  else
    let candidate = iced#nrepl#ns#alias#find_existing_alias(a:ns_name)
    if empty(candidate)
      let candidate = ''
    endif
    let ns_alias = iced#compat#trim(input('Alias: ', candidate))
  endif

  call iced#nrepl#ns#util#add(a:ns_name, ns_alias)

  let msg = ''
  if empty(ns_alias)
    let msg = printf(iced#message#get('ns_added'), a:ns_name)
  else
    let msg = printf(iced#message#get('ns_added_as'), a:ns_name, ns_alias)
  endif
  call iced#message#info_str(msg)
endfunction

function! s:ns_list(resp) abort
  if !has_key(a:resp, 'ns-list') | return iced#message#error('ns_list_error') | endif
  let namespaces = get(a:resp, 'ns-list', [])
  let favorites = get(g:iced#ns#favorites, iced#nrepl#current_session_key(), {})
  let namespaces = s:L.uniq(s:L.concat([namespaces, keys(favorites)]))

  call iced#selector({
        \ 'candidates': namespaces,
        \ 'accept': {_, ns_name -> s:add(ns_name)}
        \ })
endfunction

function! iced#nrepl#ns#refactor#add(ns_name) abort
  if empty(a:ns_name)
    call iced#nrepl#op#cider#ns_list(funcref('s:ns_list'))
  else
    call s:add(a:ns_name)
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
