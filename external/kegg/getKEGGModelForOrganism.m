function model=getKEGGModelForOrganism(organismID,fastaFile,dataDir,outDir,...
    keepUndefinedStoich,keepIncomplete,keepGeneral,cutOff,minScoreRatioG,...
    minScoreRatioKO,maxPhylDist,nSequences)
% getKEGGModelForOrganism
%   Reconstructs a genome-scale metabolic model based on protein homology to the
%   orthologies in KEGG
%
%   organismID      	three letter abbreviation of the organism (as used in
%                       KEGG). If not available, use a closely related
%                       species. This is used for determing the
%                       phylogenetic distance.
%   fastaFile           a FASTA file that contains the protein sequences of
%                       the organism for which to reconstruct a model (opt,
%                       if no FASTA file is supplied then a model is
%                       reconstructed based only on the organism
%                       abbreviation. This option ignores all settings except for
%                       keepUndefinedStoich, keepIncomplete and keepGeneral)
%   dataDir             directory for which to retrieve the input data.
%                       Should contain a combination of these sub-folders:
%                       -dataDir\keggdb
%                           The KEGG database files used in 1a (see below).
%                       -dataDir\fasta
%                           The multi-FASTA files generated in 1b or
%                           downloaded from the RAVEN Toolbox homepage (see
%                           below)
%                       -dataDir\aligned
%                           The aligned FASTA files as generated in 2a (see
%                           below)
%                       -dataDir\hmms
%                           The Hidden Markov Models as generated in 2b or
%                           downloaded from the RAVEN Toolbox homepage (see
%                           below)
%                       (opt, see note about fastaFile. Note that in order to
%                       rebuild the KEGG model from a database dump, as opposed to
%                       using the version supplied with RAVEN, you would still need
%                       to supply this)
%   outDir              directory to save the results from the quering of
%                       the Hidden Markov models. The output is specific
%                       for the input sequences and the settings used. It
%                       is stored in this manner so that the function can
%                       continue if interrupted or if it should run in
%                       parallell. Be careful not to leave output files
%                       from different organisms or runs with different
%                       settings in the same folder. They will not be
%                       overwritten (opt, default is a temporary dir where
%                       all *.out files are deleted before and after doing
%                       the reconstruction)
%   keepUndefinedStoich include reactions in the form n A <=> n+1 A. These
%                       will be dealt with as two separate metabolites 
%                       (opt, default true)
%   keepIncomplete      include reactions which have been labelled as
%                       "incomplete", "erroneous" or "unclear" (opt,
%                       default true)
%   keepGeneral         include reactions which have been labelled as
%                       "general reaction". These are reactions on the form
%                       "an aldehyde <=> an alcohol", and are therefore
%                       unsuited for modelling purposes. Note that not all
%                       reactions have this type of annotation, and the
%                       script will therefore not be able to remove all
%                       such reactions (opt, default false)
%   cutOff              significans score from HMMer needed to assign genes
%                       to a KO (opt, default 10^-50)
%   minScoreRatioG      a gene is only assigned to KOs for which the score
%                       is >=log(score)/log(best score) for that gene. 
%                       This is to prevent that a gene which clearly belongs 
%                       to one KO is assigned also to KOs with much lower 
%                       scores (opt, default 0.8 (lower is less strict))
%   minScoreRatioKO     ignore genes in a KO if their score is
%                       <log(score)/log(best score in KO). This is to
%                       "prune" KOs which have many genes and where some
%                       are clearly a better fit
%                       (opt, default 0.3 (lower is less strict))
%   maxPhylDist         -1: only use sequences from the same domain
%                       (Prokaryota, Eukaryota)
%                       other (positive) value: only use sequences for
%                       organisms where the phylogenetic distance is at
%                       the most this large (as calculated in getPhylDist)
%                       (opt, default Inf, which means that all sequences will
%                       be used)
%   nSequences          for each KO, use up to this many sequences from 
%                       the most closely related species. This is mainly to
%                       speed up the alignment process for KOs with very
%                       many genes (opt, default inf)
%
%   model               the reconstructed model
%
%   PLEASE READ THIS: The input to this function can be confusing, because
%   it is intended to be run in parallell on a cluster or in multiple sessions.
%   It therefore saves a lot of intermediate results to disc. This also
%   serves the purpose of not having to do reduntant calculations. This,
%   however, comes with the disadvantage of somewhat trickier handling.
%   This is what this function does:
%
%   1a. Downloads relevant parts from the KEGG FTP and constructs a general
%       RAVEN model representing the metabolic network. This output is 
%       distributed with RAVEN (it's in the raven\kegg directory). Delete
%       those files to rerun this parsing.
%   1b. Generates FASTA files from the downloaded KEGG files. One
%       multi-FASTA file for each KO in KEGG is generated. These
%       multi-fasta files can be downloaded from the RAVEN Toolbox
%       homepage if you do not have access to the KEGG FTP or don't want to
%       do this time-consuming parsing. Just be sure that you actually need
%       them first (see below)
%
%   These steps only have to be redone every time KEGG updates their
%   database (or rather when the updates are large enough to warrant
%   rerunning this part). Many user would probably never use this feature.
%
%   2a. Does alignment of the multi-FASTA files for future use. This uses the
%       settings "useEvDist" and "nSequences" to control which sequences
%       should be used for constructing Hidden Markov models (HMMs), and
%       later for matching your sequences to. 
%   2b. Trains Hidden Markov models using HMMer for each of the aligned
%       FASTA files.
%
%	The most common alternatives here would be to use sequences from only
%   eukaryotes, only prokaryotes or all sequences in KEGG. The Hidden Markov
%   models for those options can be downloaded from the RAVEN Toolbox
%   homepage. This is normally the most convenient way, but if you would
%   like to use, for example, only fungal sequences for training the HMMs
%   then you need to run this part.
%
%   3a. Queries the HMMs with sequences for the organism you are making a
%       model for. This step uses both the output from step 1a and from 2b.
%   3b. Constructs a model based on the fit to the HMMs and the chosen
%       parameters.
%
%   These steps are specific to the organism for which you are reconstructing
%   the model.
%
%   In principle the function looks at which output that is already available
%   and runs runs only the parts that are required for step 3. This means
%   that (see the definition of the parameters for details):
%   -1a is only performed if there are no KEGG model files in the raven\kegg
%   directory
%   -1b is only performed if not all required HMMs OR aligned FASTA files
%   OR multi-FASTA files exist in the defined dataDir. This means that this
%   step is skipped if the FASTA files or HMMs are downloaded from the RAVEN
%   Toolbox homepage instead. If not all files exist it will try to find
%   the KEGG database files in dataDir. If it cannot find them it will try
%   to download them via the KEGG FTP.
%   -2a is only performed if not all required HMMs OR aligned FASTA files
%   files exist in the defined dataDir. This means that this step is skipped
%   if the HMMs are downloaded from the RAVEN Toolbox homepage instead.
%   -2b is only performed if not all required HMMs exist in the defined
%   dataDir. This means that this step is skipped if the FASTA files or
%   HMMs are downloaded from the RAVEN Toolbox homepage instead.
%   -3a is performed for the required HMMs for which no corresponding .out
%   file exists in outDir. This is just a way to enable the function to be
%   run in parallell or to resume if interrupeted.
%   -3b is always performed.
%
%   Usage: model=getKEGGModelForOrganism(organismID,fastaFile,dataDir,outDir,...
%    keepUndefinedStoich,keepIncomplete,keepGeneral,cutOff,minScoreRatioG,...
%    minScoreRatioKO,maxPhylDist,nSequences)
%
%   Rasmus Agren, 2013-11-22
%

if nargin<2
    fastaFile=[];
end
if nargin<3
    dataDir=[];
end
if nargin<4
    outDir=[];
end
if isempty(outDir)
    outDir=tempdir;
    %Delete all *.out files if any exist
    delete(fullfile(outDir,'*.out'));
end
if nargin<5
    keepUndefinedStoich=true;
end
if nargin<6
    keepIncomplete=true;
end
if nargin<7
    keepGeneral=true;
end
if nargin<8
    cutOff=10^-50;
end
if nargin<9
    minScoreRatioG=0.8;
end
if nargin<10
    minScoreRatioKO=0.3;
end    
if nargin<11
    maxPhylDist=inf; %Include all sequences for each reaction
end
if nargin<12
    nSequences=inf; %Include all sequences for each reaction
end

%Check if the fasta-file contains '/' or'\'. If not then it's probably just
%a file name. It is then merged with the current folder
if any(fastaFile)
    if ~any(strfind(fastaFile,'\')) && ~any(strfind(fastaFile,'/'))
        fastaFile=fullfile(pwd,fastaFile);
    end
    %Create the required sub-folders in dataDir if they dont exist
    if ~exist(fullfile(dataDir,'keggdb'),'dir')
        mkdir(dataDir,'keggdb');
    end
    if ~exist(fullfile(dataDir,'fasta'),'dir')
        mkdir(dataDir,'fasta');
    end
    if ~exist(fullfile(dataDir,'aligned'),'dir')
        mkdir(dataDir,'aligned');
    end
    if ~exist(fullfile(dataDir,'hmms'),'dir')
        mkdir(dataDir,'hmms');
    end
    if ~exist(outDir,'dir')
        mkdir(outDir);
    end
end

%First generate the full KEGG model. The dataDir mustn't be supplied as
%there is also an internal RAVEN version available
if any(dataDir)
    [model, KOModel]=getModelFromKEGG(fullfile(dataDir,'keggdb'),keepUndefinedStoich,keepIncomplete,keepGeneral);
else
    [model, KOModel]=getModelFromKEGG([],keepUndefinedStoich,keepIncomplete,keepGeneral);
end
fprintf('Completed generation of KEGG model\n');
model.id=organismID;
model.c=zeros(numel(model.rxns),1);

%If no FASTA file is supplied, then just remove all genes which are not for
%the given organism ID
if isempty(fastaFile)
    %All IDs are three letters
    I=cellfun(@(x) strcmpi(x(1:3),organismID),model.genes);
    
    %Remove those genes
    model.genes=model.genes(I);
    model.rxnGeneMat=model.rxnGeneMat(:,I);
end

%First remove all reactions without genes
hasGenes=any(model.rxnGeneMat,2);

model=removeReactions(model,~hasGenes,true);

%If no FASTA file is supplied, then we're done here
if isempty(fastaFile)
    return;
end

%Trim the genes so that they only contain information that can be matched
%to the KEGG file of protein sequences (remove all information after first
%parenthesis)

%NOTE: For some reason the organism abbreviation should be in lower case in
%this database. Fix this here
for i=1:numel(KOModel.genes)    
    parIndex=strfind(KOModel.genes{i},'(');
    if any(parIndex)
       KOModel.genes{i}=KOModel.genes{i}(1:parIndex-1); 
    end
    colIndex=strfind(KOModel.genes{i},':');
    KOModel.genes{i}=[lower(KOModel.genes{i}(1:colIndex-1)) KOModel.genes{i}(colIndex:end)];
end

%Create a phylogenetic distance structure
phylDistStruct=getPhylDist(fullfile(dataDir,'keggdb'),maxPhylDist==-1);
[crap phylDistId]=ismember(model.id,phylDistStruct.ids);
fprintf('Completed creation of phylogenetic distance matrix\n');

%Calculate the real maximal distance now. An abitary large number of 1000 is
%used for the "all in kingdom" or "all sequences" options. This is a bit
%inconvenient way to do it, but it's to make it fit with some older code
if isinf(maxPhylDist) || maxPhylDist==-1
    maxPhylDist=1000;
end

%Get the KO ids for which files have been generated. Maybe not the neatest
%way..
fastaFiles=listFiles(fullfile(dataDir,'fasta','*.fa'));
alignedFiles=listFiles(fullfile(dataDir,'aligned','*.fa'));
alignedWorking=listFiles(fullfile(dataDir,'aligned','*.faw'));
hmmFiles=listFiles(fullfile(dataDir,'hmms','*.hmm'));
outFiles=listFiles(fullfile(outDir,'*.out'));

%Check if multi-FASTA files should be generated. This should only be
%performed if there are IDs in the KOModel structure that haven't been
%parsed yet
missingFASTA=setdiff(KOModel.rxns,[fastaFiles;alignedFiles;hmmFiles;outFiles]);

if ~isempty(missingFASTA)
    if ~exist(fullfile(dataDir,'keggdb','genes.pep'),'file')
        %If no sequence file exists then download from KEGG
        downloadKEGG(fullfile(dataDir,'keggdb'));
    end
    %Only construct models for KOs which don't have files already
    fastaModel=removeReactions(KOModel,setdiff(KOModel.rxns,missingFASTA),true,true);
    %Permute the order of the KOs in the model so that constructMultiFasta
    %can be run on several processors at once
    fastaModel=permuteModel(fastaModel,randperm(RandStream.create('mrg32k3a','Seed',cputime()),numel(fastaModel.rxns)),'rxns');
    constructMultiFasta(fastaModel,fullfile(dataDir,'keggdb','genes.pep'),fullfile(dataDir,'fasta'));
end
fprintf('Completed generation of multi-FASTA files\n');

%Get the directory for RAVEN Toolbox. This is to get the path to the third
%party software used
[ST I]=dbstack('-completenames');
ravenPath=fileparts(fileparts(fileparts(ST(I).file))));

%Check if alignment of FASTA files should be performed
missingAligned=setdiff(KOModel.rxns,[alignedFiles;hmmFiles;alignedWorking;outFiles]);
if ~isempty(missingAligned)
    missingAligned=missingAligned(randperm(RandStream.create('mrg32k3a','Seed',cputime()),numel(missingAligned)));
    %Align all sequences using CLUSTALW
    for i=1:numel(missingAligned)
        %This is checked here because it could be that it is created by a
        %parallell process. The faw-files are saved as temporary files to
        %keppt track of which files are being worked on
        if ~exist(fullfile(dataDir,'aligned',[missingAligned{i} '.faw']),'file') && ~exist(fullfile(dataDir,'aligned',[missingAligned{i} '.fa']),'file')
            %Check that the multi-FASTA file exists. It should do so since
            %we are saving empty files as well. Print a warning and
            %continue if not.
            if ~exist(fullfile(dataDir,'fasta',[missingAligned{i} '.fa']),'file')
                dispEM(['WARNING: The multi-FASTA file for ' missingAligned{i} ' does not exist'],false);
                continue;
            end
            
            %If the multi-FASTA file is empty then save an empty aligned
            %file and continue
            s=dir(fullfile(dataDir,'fasta',[missingAligned{i} '.fa']));
            if s.bytes<=0
                fid=fopen(fullfile(dataDir,'aligned',[missingAligned{i} '.fa']),'w');
                fclose(fid);
                continue;
            end
            
            %Create an empty file to prevent other threads to start to work on the same alignment
            fid=fopen(fullfile(dataDir,'aligned',[missingAligned{i} '.faw']),'w');
            fclose(fid);
            
            %First load the FASTA file, then select up to nSequences sequences
            %of the most closely related species, apply any constraints from
            %maxPhylDist, and save it as a temporary file, and create the
            %model from that

            fastaStruct=fastaread(fullfile(dataDir,'fasta',[missingAligned{i} '.fa']));
            phylDist=inf(numel(fastaStruct),1);
            for j=1:numel(fastaStruct)
               %Get the organism abbreviation
               index=strfind(fastaStruct(j).Header,':');
               if any(index)
                    abbrev=fastaStruct(j).Header(1:index(1)-1);
                    [crap index]=ismember(abbrev,phylDistStruct.ids);
                    if any(index)
                        phylDist(j)=phylDistStruct.distMat(index(1),phylDistId);
                    end
               end
            end

            %Inf means that it should not be included
            phylDist(phylDist>maxPhylDist)=[];

            %Sort based on phylDist
            [crap order]=sort(phylDist);

            %Save the first nSequences hits to a temporary FASTA file
            if nSequences<=numel(fastaStruct)
                fastaStruct=fastaStruct(order(1:nSequences));
            else
                fastaStruct=fastaStruct(order);
            end
            
            %Do the alignment if there are more than one sequences,
            %otherwise just save the sequence (or an empty file)
            if numel(fastaStruct)>1
                tmpFile=tempname;
                fastawrite(tmpFile,fastaStruct);

                %Do the alignment for this file
                [status output]=system([fullfile(ravenPath,'external','software','clustalw2','clustalw2') ' -infile="' tmpFile '" -align -outfile="' fullfile(dataDir,'aligned',[missingAligned{i} '.faw']) '" -output=FASTA -type=PROTEIN -OUTORDER=INPUT']);
                if status~=0
                	dispEM(['Error when performing alignment of ' missingAligned{i} ':\n' output]); 
                end
                %Remove the old tempfile
                if exist(tmpFile, 'file')
                   delete([tmpFile '*']);
                end
            else
                %If there is only one sequence then it's not possible to do a
                %multiple alignment. Just print the sequence instead. An
                %empty file was written previously so that doesn't have to
                %be dealt with
                if numel(fastaStruct)==1
                    %CLUSTALW only uses the first word as gene name. This
                    %doesn't really have an effect, but might as well be
                    %consistent
                    I=regexp(fastaStruct.Header,' ','split');
                    fastaStruct.Header=strrep(I{1},':','_');
                    fastawrite(fullfile(dataDir,'aligned',[missingAligned{i} '.faw']),fastaStruct);
                end
            end
            %Move the temporary file to the real one
            movefile(fullfile(dataDir,'aligned',[missingAligned{i} '.faw']),fullfile(dataDir,'aligned',[missingAligned{i} '.fa']),'f');
        end
    end
end
fprintf('Completed multiple alignment of sequences\n');

%Check if training of Hidden Markov models should be performed
missingHMMs=setdiff(KOModel.rxns,[hmmFiles;outFiles]);
if ~isempty(missingHMMs)
    missingHMMs=missingHMMs(randperm(RandStream.create('mrg32k3a','Seed',cputime()),numel(missingHMMs)));
    
    %Train models for all missing KOs
    for i=1:numel(missingHMMs)
        %This is checked here because it could be that it is created by a
        %parallell process
        if ~exist(fullfile(dataDir,'hmms',[missingHMMs{i} '.hmm']),'file') && ~exist(fullfile(dataDir,'hmms',[missingHMMs{i} '.hmw']),'file')
            %Check that the aligned FASTA file exists. It could be that it
            %is still being worked on by some other instance of the
            %program (the .faw file should then exist). This should not
            %happen on a single computer. I don't throw an error, because
            %it should finalize the ones it can.
            if ~exist(fullfile(dataDir,'aligned',[missingHMMs{i} '.fa']),'file')
            	dispEM(['The aligned FASTA file for ' missingHMMs{i} ' does not exist'],false);
                continue;
            end
            
            %If the multi-FASTA file is empty then save an empty aligned
            %file and continue
            s=dir(fullfile(dataDir,'aligned',[missingHMMs{i} '.fa']));
            if s.bytes<=0
                fid=fopen(fullfile(dataDir,'hmms',[missingHMMs{i} '.hmm']),'w');
                fclose(fid);
                continue;
            end
            %Create a temporary file to indicate that it is working on the
            %KO. This is because hmmbuild cannot overwrite existing files.
            fid=fopen(fullfile(dataDir,'hmms',[missingHMMs{i} '.hmw']),'w');
            fclose(fid);
                
            %Create HMM. This is saved with a "hm" ending to indicate that
            %it hasn't been calibrated yet. This is because I want to be
            %able to see which models are uncalibrated if something goes
            %wrong
            [status output]=system([fullfile(ravenPath,'external','software','hmmer-2.3','hmmbuild') ' "' fullfile(dataDir,'hmms',[missingHMMs{i} '.hm']) '" "' fullfile(dataDir,'aligned',[missingHMMs{i} '.fa']) '"']);
            if status~=0
            	dispEM(['Error when training HMM for ' missingHMMs{i} ':\n' output]);
            end
            
            %This is only available for linux
            if ~ispc
                [status output]=system([fullfile(ravenPath,'external','software','hmmer-2.3','hmmcalibrate') ' "' fullfile(dataDir,'hmms',[missingHMMs{i} '.hm']) '"']);
                if status~=0
                    %This check is because some HMMs gives an error saying
                    %that the number of iterations might be too low.
                    %However, raising it doesn't have any effect. The error
                    %is therefore ignored and the uncalibrated model is
                    %used
                    if isempty(strfind(output,'--num may be set too small?'))
                        delete(fullfile(dataDir,'hmms',[missingHMMs{i} '.hm']));
                        dispEM(['Error when calibrating HMM for ' missingHMMs{i} ':\n' output]);
                    else
                        dispEM(['Cannot calibrate the HMM for ' missingHMMs{i} '. Using uncalibrated version'],false);
                    end
                end
            end
            %Move the temporary file to the real one
            movefile(fullfile(dataDir,'hmms',[missingHMMs{i} '.hm']),fullfile(dataDir,'hmms',[missingHMMs{i} '.hmm']),'f');
            %Delete the temporary file
            delete(fullfile(dataDir,'hmms',[missingHMMs{i} '.hmw']));
        end
    end
end
fprintf('Completed generation of HMMs\n');

%Check which new .out files that should be generated
%Check if training of Hidden Markov models should be performed
missingOUT=setdiff(KOModel.rxns,outFiles);
if ~isempty(missingOUT)
    missingOUT=missingOUT(randperm(RandStream.create('mrg32k3a','Seed',cputime()),numel(missingOUT)));
    for i=1:numel(missingOUT)
        %This is checked here because it could be that it is created by a
        %parallell process
        if ~exist(fullfile(outDir,[missingOUT{i} '.out']),'file')
            %Check that the HMM file exists. It should do so since
            %we are saving empty files as well. Print a warning and
            %continue if not.
            if ~exist(fullfile(dataDir,'hmms',[missingOUT{i} '.hmm']),'file')
            	dispEM(['The HMM file for ' missingOUT{i} ' does not exist'],false);
                continue;
            end
            
            %Save an empty file to prevent several threads working on the
            %same file
            fid=fopen(fullfile(outDir,[missingOUT{i} '.out']),'w');
            fclose(fid);
            
            %If the HMM file is empty then save an out file and continue
            s=dir(fullfile(dataDir,'hmms',[missingOUT{i} '.hmm']));
            if s.bytes<=0
                continue;
            end
            
            %Check each gene in the input file against this model
            [status output]=system([fullfile(ravenPath,'external','software','hmmer-2.3','hmmsearch') ' "' fullfile(dataDir,'hmms',[missingOUT{i} '.hmm']) '" "' fastaFile '"']);
            if status~=0
            	dispEM(['Error when querying HMM for ' missingOUT{i} ':\n' output]); 
            end

            %Save the output to a file
            fid=fopen(fullfile(outDir,[missingOUT{i} '.out']),'w');
            fwrite(fid,output);
            fclose(fid);
        end 
    end
end
fprintf('Completed matching to HMMs\n');
            
%***Begin retrieving the output and putting together the resulting model

%Retrieve matched genes from the HMMs
koGeneMat=zeros(numel(KOModel.rxns),3000); %Make room for 3000 genes
genes=cell(3000,1);
%Store the best score for a gene in a hash list (since I will be searching
%many times)
hTable = java.util.Hashtable;

geneCounter=0;
for i=1:numel(KOModel.rxns)
    if exist(fullfile(outDir,[KOModel.rxns{i} '.out']), 'file')
        fid=fopen(fullfile(outDir,[KOModel.rxns{i} '.out']),'r');
        beginMatches=false;
        while 1
            %Get the next line
            tline = fgetl(fid);

            %Abort at end of file
            if ~ischar(tline)
                break;
            end
            
            if beginMatches==false
                %This is how the listing of matches begins
                if any(strfind(tline,'E-value '))
                    %Read one more line that is only padding
                    tline = fgetl(fid);
                    beginMatches=true;
                end
            else
                %If matches should be read
                if ~strcmp(tline,'	[no hits above thresholds]') && ~isempty(tline)
                    elements=regexp(tline,' ','split');
                    elements=elements(cellfun(@any,elements));
                    
                    %Check if the match is below the treshhold
                    score=str2num(elements{end-1});
                    gene=elements{1};
                    if score<=cutOff
                        %If the score is exactly 0, change it to a very
                        %small value to avoid NaN
                        if score==0
                           score=10^-250; 
                        end
                        %Check if the gene is added already and, is so, get
                        %the best score for it
                        I=hTable.get(gene);
                        if any(I)
                            koGeneMat(i,I)=score;    
                        else
                            geneCounter=geneCounter+1;
                            %The gene was not present yet so add it
                            hTable.put(gene,geneCounter);
                            genes{geneCounter}=gene;
                            koGeneMat(i,geneCounter)=score;
                        end
                    end
                else
                    break;
                end
            end
        end
        fclose(fid);
    end
end
koGeneMat=koGeneMat(:,1:geneCounter);

%Remove the genes for each KO that are below minScoreRatioKO.
for i=1:size(koGeneMat,1)
    J=find(koGeneMat(i,:));
    if any(J)
        koGeneMat(i,J(log(koGeneMat(i,J))/log(min(koGeneMat(i,J)))<minScoreRatioKO))=0;
    end
end

%Remove the KOs for each gene that are below minScoreRatioG
for i=1:size(koGeneMat,2)
    J=find(koGeneMat(:,i));
    if any(J)
        koGeneMat(J(log(koGeneMat(J,i))/log(min(koGeneMat(J,i)))<minScoreRatioG),i)=0;
    end
end

%Create the new model
model.genes=genes(1:geneCounter);
model.grRules=cell(numel(model.rxns),1);
model.grRules(:)={''};
model.rxnGeneMat=sparse(numel(model.rxns),numel(model.genes));

%Loop through the reactions and add the corresponding genes
for i=1:numel(model.rxns)
    if isstruct(model.rxnMiriams{i})
        %Get all KOs
        I=find(strcmpi(model.rxnMiriams{i}.name,'urn:miriam:kegg.ko'));
        KOs=model.rxnMiriams{i}.value(I);
        %Find the KOs and the corresponding genes
        J=ismember(KOModel.rxns,KOs);
        [crap K]=find(koGeneMat(J,:));
        
        if any(K)
            model.rxnGeneMat(i,K)=1;
            %Also delete KOs for which no genes were found. If no genes at all
            %were matched to the reaction it will be deleted later
            L=sum(koGeneMat(J,:),2)==0;
            model.rxnMiriams{i}.value(I(L))=[];
            model.rxnMiriams{i}.name(I(L))=[];
        end
    end
end

%Find and delete all reactions without any genes. This also removes genes
%that are not used (which could happen because minScoreRatioG and
%minScoreRatioKO)
I=sum(model.rxnGeneMat,2)==0;
model=removeReactions(model,I,true,true);

%Add the gene associations as 'or'
for i=1:numel(model.rxns)
    %Find the involved genes
    I=find(model.rxnGeneMat(i,:));
    model.grRules{i}=['(' model.genes{I(1)}];
    for j=2:numel(I)
        model.grRules{i}=[model.grRules{i} ' or ' model.genes{I(j)}];
    end
    model.grRules{i}=[model.grRules{i} ')'];
end
end

%Supporter function to list the files in a directory and return them as a
%cell array
function files=listFiles(directory)
    temp=dir(directory);
    files=cell(numel(temp),1);
    for i=1:numel(temp)
        files{i}=temp(i,1).name;
    end
    files=strrep(files,'.fa','');
    files=strrep(files,'.hmm','');
    files=strrep(files,'.out','');
    files=strrep(files,'.faw','');
end