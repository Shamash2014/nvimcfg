call plug#begin('~/.vim/plugged')

Plug 'scrooloose/nerdtree'
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-git'
Plug 'tpope/vim-fugitive'
Plug 'ikaros/smpl-vim'
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
Plug 'elixir-lang/vim-elixir'
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
Plug 'slim-template/vim-slim'
Plug 'the-lambda-church/merlin'
Plug 'roman/golden-ratio'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
call plug#end()

let mapleader  = ","
set backspace=eol,start,indent
colorscheme smpl

syntax enable
filetype plugin indent on
filetype plugin on

nmap  <C-n> :NERDTreeToggle<CR>
nmap <C-k> <C-w><Up>
nmap <C-j> <C-w><Down>
nmap <C-l> <C-w><Right>
nmap <C-h> <C-w><Left>
nmap <C-P> :FZF<CR>
highlight ExtraWhitespace ctermfg=50
au BufWritePre * StripWhitespace
au Vimenter * NERDTree
set number
set expandtab
