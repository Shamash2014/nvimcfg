call plug#begin('~/.vim/plugged')

Plug 'scrooloose/nerdtree'
Plug 'pearofducks/ansible-vim'
Plug 'klen/python-mode'
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-git'
Plug 'tpope/vim-fugitive'
Plug 'ikaros/smpl-vim'
Plug 'mattn/emmet-vim'
Plug 'scrooloose/nerdcommenter'
Plug 'davidhalter/jedi-vim'
Plug 'scrooloose/syntastic'
Plug 'tpope/vim-eunuch'
Plug 'bling/vim-airline'
Plug 'tpope/vim-rails'
Plug 'tpope/vim-bundler'
Plug 'tpope/vim-sleuth'
Plug 'stephpy/vim-yaml'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-dispatch'
Plug 'majutsushi/tagbar'
Plug 'vim-erlang/vim-erlang-runtime'
Plug 'vim-erlang/vim-erlang-omnicomplete'
Plug 'isRuslan/vim-es6'
Plug 'kien/ctrlp.vim'
Plug 'godlygeek/tabular'
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-cucumber'
Plug 'renderedtext/vim-bdd'
Plug 'KurtPreston/vim-autoformat-rails'
Plug 'rgrinberg/vim-ocaml'
Plug 'OCamlPro/ocp-indent'
Plug 'raichoo/purescript-vim'
Plug 'slim-template/vim-slim'
Plug 'the-lambda-church/merlin'
Plug 'roman/golden-ratio'
Plug 'travitch/hasksyn'
Plug 'moll/vim-node'
Plug 'dag/vim2hs'
Plug 'mxw/vim-jsx'
Plug 'digitaltoad/vim-jade'
Plug 'VimClojure'
Plug 'elixir-lang/vim-elixir'
Plug 'thinca/vim-ref'
Plug 'awetzel/elixir.nvim', { 'do': 'yes \| ./install.sh' }
Plug 'townk/vim-autoclose'
Plug 'eugen0329/vim-esearch'
Plug 'kivy/kivy'
Plug 'tpope/vim-classpath'
Plug 'nvie/vim-flake8'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'guns/vim-clojure-static'
Plug 'junegunn/rainbow_parentheses.vim'
Plug 'guns/vim-clojure-highlight'
Plug 'tpope/vim-fireplace'
Plug 'tpope/vim-sexp-mappings-for-regular-people'
Plug 'guns/vim-sexp'
Plug 'tpope/vim-repeat'
Plug 'kassio/neoterm'
Plug 'bhurlow/vim-parinfer'
Plug 'Vim-R-plugin2'
Plug 'slashmili/alchemist.vim'
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'bfredl/nvim-ipy'
call plug#end()

let mapleader  = ","
set backspace=eol,start,indent
colorscheme smpl

syntax enable
filetype plugin indent on
filetype plugin on
:set cursorline
:set ts=4
:set lazyredraw
:set showmatch

:nmap  <C-n> :NERDTreeToggle<CR>
:nmap <C-k> <C-w><Up>
:nmap <C-j> <C-w><Down>
:nmap <C-l> <C-w><Right>
:nmap <C-h> <C-w><Left>
:nmap <C-P> :FZF<CR>
highlight ExtraWhitespace ctermfg=50
au BufWritePre * StripWhitespace
au Vimenter * NERDTree
:set number
:set expandtab
:set foldmethod=indent
:set foldlevel=99
:set encoding=utf-8

:tnoremap <Esc> <C-\><C-n>
:tnoremap <A-h> <C-\><C-n><C-w>h
:tnoremap <A-j> <C-\><C-n><C-w>j
:tnoremap <A-k> <C-\><C-n><C-w>k
:tnoremap <A-l> <C-\><C-n><C-w>l
:nnoremap <A-h> <C-w>h
:nnoremap <A-j> <C-w>j
:nnoremap <A-k> <C-w>k
:nnoremap <A-l> <C-w>l
:nnoremap <space> za

let g:jsx_ext_required = 0
let g:ctrlp_match_window = 'bottom,order:ttb'
let g:ctrlp_switch_buffer = 0
let g:ctrlp_working_path_mode = 0
let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden -g ""'

let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 1
